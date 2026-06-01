package online.users;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Md5;
import sys.FileSystem;
import sys.io.File;

typedef OnlineUser =
{
	var id:String;
	var username:String;
	var platform:String;
	var engineVersion:String;
	var joinedAt:Float;
	var ?avatar:String;
	var ?status:String;
}

typedef UserSession =
{
	var token:String;
	var user:OnlineUser;
	var expiresAt:Float;
}

class OnlineUsers
{
	static final BASE_URL:String       = "https://api.brenninhoengine.com/users";
	static final SESSION_FILE:String   = "saves/session.json";
	static final POLL_INTERVAL:Float   = 30000;
	static final SESSION_DURATION:Float = 3600000;
	static final TIMEOUT:Int           = 10;

	public static var isLoggedIn:Bool             = false;
	public static var currentUser:OnlineUser      = null;
	public static var currentSession:UserSession  = null;
	public static var onlineUsers:Array<OnlineUser> = [];
	public static var onUserJoined:OnlineUser->Void = null;
	public static var onUserLeft:OnlineUser->Void   = null;
	public static var onUsersUpdated:Array<OnlineUser>->Void = null;

	private static var _pollTimer:Float  = 0.0;
	private static var _initialized:Bool = false;
	private static var _lastUserIds:Array<String> = [];

	public static function init():Void
	{
		if (_initialized)
			return;

		_initialized = true;
		_loadSession();
	}

	public static function login(username:String, ?onSuccess:OnlineUser->Void, ?onError:String->Void):Void
	{
		if (!online.Online.isConnected)
		{
			if (onError != null) onError('No internet connection.');
			return;
		}

		if (username == null || username.trim().length < 2)
		{
			if (onError != null) onError('Username must be at least 2 characters.');
			return;
		}

		var payload:String = Json.stringify({
			username:      username.trim(),
			platform:      backend.system.Main.platform,
			engineVersion: states.MainMenuState.psychEngineVersion.trim(),
			token:         _generateToken(username)
		});

		var http:Http = new Http('$BASE_URL/login');
		http.cnxTimeout = TIMEOUT;
		http.addHeader('Content-Type', 'application/json');
		http.setPostData(payload);

		http.onData = function(data:String):Void
		{
			try
			{
				var parsed:Dynamic    = Json.parse(data);
				var user:OnlineUser   = _parseUser(parsed.user);
				var session:UserSession = {
					token:     parsed.token,
					user:      user,
					expiresAt: Date.now().getTime() + SESSION_DURATION
				};

				currentUser    = user;
				currentSession = session;
				isLoggedIn     = true;

				_saveSession(session);
				_fetchOnlineUsers(null, null);

				if (onSuccess != null) onSuccess(user);
			}
			catch (e:Dynamic)
			{
				if (onError != null) onError('Failed to parse login response: $e');
			}
		};

		http.onError = function(msg:String):Void
		{
			if (onError != null) onError('Login failed: $msg');
		};

		http.request(true);
	}

	public static function logout(?onSuccess:Void->Void):Void
	{
		if (!isLoggedIn || currentSession == null)
			return;

		var http:Http = new Http('$BASE_URL/logout');
		http.cnxTimeout = TIMEOUT;
		http.addHeader('Content-Type', 'application/json');
		http.addHeader('Authorization', 'Bearer ${currentSession.token}');
		http.setPostData(Json.stringify({ token: currentSession.token }));

		http.onData = function(_:String):Void
		{
			_clearSession();
			if (onSuccess != null) onSuccess();
		};

		http.onError = function(_:String):Void
		{
			_clearSession();
			if (onSuccess != null) onSuccess();
		};

		http.request(true);
	}

	public static function update(elapsed:Float):Void
	{
		if (!isLoggedIn || !online.Online.isConnected)
			return;

		_pollTimer += elapsed * 1000;

		if (_pollTimer >= POLL_INTERVAL)
		{
			_pollTimer = 0.0;
			_fetchOnlineUsers(null, null);
			_refreshSession();
		}
	}

	public static function fetchUsers(?onSuccess:Array<OnlineUser>->Void, ?onError:String->Void):Void
	{
		if (!online.Online.isConnected)
		{
			if (onError != null) onError('No internet connection.');
			return;
		}
		_fetchOnlineUsers(onSuccess, onError);
	}

	public static function updateStatus(status:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isLoggedIn || currentSession == null)
		{
			if (onError != null) onError('Not logged in.');
			return;
		}

		var http:Http = new Http('$BASE_URL/status');
		http.cnxTimeout = TIMEOUT;
		http.addHeader('Content-Type', 'application/json');
		http.addHeader('Authorization', 'Bearer ${currentSession.token}');
		http.setPostData(Json.stringify({ status: status }));

		http.onData = function(_:String):Void
		{
			if (currentUser != null)
				currentUser.status = status;
			if (onSuccess != null) onSuccess();
		};

		http.onError = function(msg:String):Void
		{
			if (onError != null) onError('Failed to update status: $msg');
		};

		http.request(true);
	}

	public static function getUserCount():Int
	{
		return onlineUsers.length;
	}

	public static function getUserById(id:String):Null<OnlineUser>
	{
		for (user in onlineUsers)
			if (user.id == id)
				return user;
		return null;
	}

	public static function getUsersByPlatform(platform:String):Array<OnlineUser>
	{
		return onlineUsers.filter((u:OnlineUser) -> u.platform == platform);
	}

	public static function isSessionValid():Bool
	{
		if (currentSession == null) return false;
		return Date.now().getTime() < currentSession.expiresAt;
	}

	private static function _fetchOnlineUsers(?onSuccess:Array<OnlineUser>->Void, ?onError:String->Void):Void
	{
		var http:Http = new Http('$BASE_URL/list');
		http.cnxTimeout = TIMEOUT;

		if (currentSession != null)
			http.addHeader('Authorization', 'Bearer ${currentSession.token}');

		http.onData = function(data:String):Void
		{
			try
			{
				var parsed:Dynamic       = Json.parse(data);
				var rawUsers:Array<Dynamic> = parsed.users;
				var newUsers:Array<OnlineUser> = rawUsers.map((u:Dynamic) -> _parseUser(u));

				_detectChanges(newUsers);
				onlineUsers = newUsers;
				_lastUserIds = newUsers.map((u:OnlineUser) -> u.id);

				if (onUsersUpdated != null) onUsersUpdated(onlineUsers);
				if (onSuccess != null)      onSuccess(onlineUsers);
			}
			catch (e:Dynamic)
			{
				if (onError != null) onError('Failed to parse users: $e');
			}
		};

		http.onError = function(msg:String):Void
		{
			if (onError != null) onError('Failed to fetch users: $msg');
		};

		http.request(false);
	}

	private static function _detectChanges(newUsers:Array<OnlineUser>):Void
	{
		var newIds:Array<String> = newUsers.map((u:OnlineUser) -> u.id);

		if (onUserJoined != null)
			for (user in newUsers)
				if (!_lastUserIds.contains(user.id))
					onUserJoined(user);

		if (onUserLeft != null)
			for (user in onlineUsers)
				if (!newIds.contains(user.id))
					onUserLeft(user);
	}

	private static function _refreshSession():Void
	{
		if (currentSession == null || !isSessionValid()) return;

		var http:Http = new Http('$BASE_URL/refresh');
		http.cnxTimeout = TIMEOUT;
		http.addHeader('Authorization', 'Bearer ${currentSession.token}');
		http.setPostData(Json.stringify({ token: currentSession.token }));

		http.onData = function(data:String):Void
		{
			try
			{
				var parsed:Dynamic = Json.parse(data);
				currentSession.token     = parsed.token;
				currentSession.expiresAt = Date.now().getTime() + SESSION_DURATION;
				_saveSession(currentSession);
			}
			catch (e:Dynamic) {}
		};

		http.onError = function(_:String):Void {};
		http.request(true);
	}

	private static function _loadSession():Void
	{
		if (!FileSystem.exists(SESSION_FILE)) return;

		try
		{
			var content:String    = File.getContent(SESSION_FILE);
			var parsed:Dynamic    = Json.parse(content);
			var session:UserSession = {
				token:     parsed.token,
				user:      _parseUser(parsed.user),
				expiresAt: parsed.expiresAt
			};

			if (Date.now().getTime() < session.expiresAt)
			{
				currentSession = session;
				currentUser    = session.user;
				isLoggedIn     = true;
				_fetchOnlineUsers(null, null);
			}
			else
			{
				_clearSession();
			}
		}
		catch (e:Dynamic)
		{
			_clearSession();
		}
	}

	private static function _saveSession(session:UserSession):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent(SESSION_FILE, Json.stringify({
				token:     session.token,
				user:      session.user,
				expiresAt: session.expiresAt
			}));
		}
		catch (e:Dynamic) {}
	}

	private static function _clearSession():Void
	{
		isLoggedIn     = false;
		currentUser    = null;
		currentSession = null;
		onlineUsers    = [];
		_lastUserIds   = [];
		_pollTimer     = 0.0;

		try
		{
			if (FileSystem.exists(SESSION_FILE))
				FileSystem.deleteFile(SESSION_FILE);
		}
		catch (e:Dynamic) {}
	}

	private static function _parseUser(raw:Dynamic):OnlineUser
	{
		return {
			id:            Std.string(Reflect.field(raw, 'id')),
			username:      Std.string(Reflect.field(raw, 'username')),
			platform:      Std.string(Reflect.field(raw, 'platform')),
			engineVersion: Std.string(Reflect.field(raw, 'engineVersion')),
			joinedAt:      Reflect.field(raw, 'joinedAt'),
			avatar:        Reflect.field(raw, 'avatar'),
			status:        Reflect.field(raw, 'status')
		};
	}

	private static function _generateToken(username:String):String
	{
		var seed:String = username + Date.now().getTime() + backend.system.Main.platform;
		return Md5.encode(seed);
	}
}
