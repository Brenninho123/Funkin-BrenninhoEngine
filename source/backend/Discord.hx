package backend;

import lime.app.Application;
import hxdiscord_rpc.Discord;
import hxdiscord_rpc.Types;

class DiscordClient
{
	public static var isInitialized:Bool       = false;
	public static var onReady:String->Void     = null;
	public static var onError:Int->String->Void = null;
	public static var onDisconnect:Int->String->Void = null;

	private static final _defaultID:String     = '863222024192262205';
	private static final _largeImageKey:String = 'icon';

	private static var _presence:DiscordRichPresence = _makePresence();
	private static var _thread:sys.thread.Thread     = null;
	private static var _running:Bool                 = false;
	private static var _currentDetails:String        = '';
	private static var _currentState:Null<String>    = null;

	public static var clientID(default, set):String  = _defaultID;

	public static function check():Void
	{
		if (ClientPrefs.data.discordRPC)
		{
			if (!isInitialized) initialize();
		}
		else if (isInitialized) shutdown();
	}

	public static function prepare():Void
	{
		if (!isInitialized && ClientPrefs.data.discordRPC)
			initialize();

		Application.current.window.onClose.add(function():Void
		{
			if (isInitialized) shutdown();
		});
	}

	public static function initialize():Void
	{
		if (isInitialized) return;

		var handlers:DiscordEventHandlers = _makeHandlers();
		handlers.ready        = cpp.Function.fromStaticFunction(_onReady);
		handlers.disconnected = cpp.Function.fromStaticFunction(_onDisconnected);
		handlers.errored      = cpp.Function.fromStaticFunction(_onError);

		#if (hxdiscord_rpc >= "1.3.0")
		Discord.Initialize(clientID, cpp.RawPointer.addressOf(handlers), false, null);
		#elseif (hxdiscord_rpc > "1.2.4")
		Discord.Initialize(clientID, cpp.RawPointer.addressOf(handlers), false, null);
		#else
		Discord.Initialize(clientID, cpp.RawPointer.addressOf(handlers), 1, null);
		#end

		_running = true;
		_thread  = sys.thread.Thread.create(_threadLoop);

		isInitialized = true;
		changePresence();
	}

	public dynamic static function shutdown():Void
	{
		_running      = false;
		_thread       = null;
		isInitialized = false;
		Discord.Shutdown();
	}

	public static function changePresence(
		?details:String          = "Playing BrenninhoEngine'",
		?state:Null<String>      = null,
		?smallImageKey:String    = null,
		?smallImageText:String   = null,
		?hasStartTimestamp:Bool  = false,
		?endTimestamp:Float      = 0,
		?partySize:Int           = 0,
		?partyMax:Int            = 0):Void
	{
		_currentDetails = details;
		_currentState   = state;

		var startTimestamp:Float = hasStartTimestamp ? Date.now().getTime() : 0;
		if (endTimestamp > 0) endTimestamp = startTimestamp + endTimestamp;

		_presence.details        = details;
		_presence.state          = state;
		_presence.largeImageKey  = _largeImageKey;
		_presence.largeImageText = 'BrenninhoEngine v${states.MainMenuState.psychEngineVersion}';
		_presence.smallImageKey  = smallImageKey  ?? '';
		_presence.smallImageText = smallImageText ?? '';
		_presence.startTimestamp = Std.int(startTimestamp / 1000);
		_presence.endTimestamp   = Std.int(endTimestamp   / 1000);

		if (partySize > 0 && partyMax > 0)
		{
			_presence.partySize = partySize;
			_presence.partyMax  = partyMax;
		}

		updatePresence();
	}

	public static function updatePresence():Void
	{
		if (!isInitialized) return;
		Discord.UpdatePresence(cpp.RawConstPointer.addressOf(_presence));
	}

	public static function clearPresence():Void
	{
		if (!isInitialized) return;
		Discord.ClearPresence();
	}

	public static function resetClientID():Void
	{
		clientID = _defaultID;
	}

	public static function getCurrentDetails():String   { return _currentDetails; }
	public static function getCurrentState():Null<String> { return _currentState; }

	#if (MODS_ALLOWED && DISCORD_ALLOWED)
	public static function loadModRPC():Void
	{
		var pack:Dynamic = Mods.getPack();
		if (pack == null) return;

		var modID:String = Reflect.field(pack, 'discordRPC');
		if (modID != null && modID.length > 0 && modID != clientID)
			clientID = modID;
	}
	#end

	#if LUA_ALLOWED
	public static function addLuaCallbacks(lua:State):Void
	{
		Lua_helper.add_callback(lua, 'changeDiscordPresence', function(
			details:String, ?state:Null<String>,
			?smallImageKey:String, ?smallImageText:String,
			?hasStartTimestamp:Bool, ?endTimestamp:Float,
			?partySize:Int, ?partyMax:Int):Void
		{
			changePresence(details, state, smallImageKey, smallImageText,
				hasStartTimestamp ?? false,
				endTimestamp      ?? 0,
				partySize         ?? 0,
				partyMax          ?? 0);
		});

		Lua_helper.add_callback(lua, 'changeDiscordClientID', function(?newID:String = null):Void
		{
			clientID = newID ?? _defaultID;
		});

		Lua_helper.add_callback(lua, 'resetDiscordPresence', function():Void
		{
			changePresence();
		});

		Lua_helper.add_callback(lua, 'clearDiscordPresence', function():Void
		{
			clearPresence();
		});

		Lua_helper.add_callback(lua, 'isDiscordInitialized', function():Bool
		{
			return isInitialized;
		});
	}
	#end

	#if HSCRIPT_ALLOWED
	public static function addHScriptCallbacks(script:scripting.HScript):Void
	{
		script.set('changeDiscordPresence', function(
			?details:String, ?state:String,
			?smallImageKey:String, ?smallImageText:String,
			?hasStartTimestamp:Bool, ?endTimestamp:Float,
			?partySize:Int, ?partyMax:Int):Void
		{
			changePresence(
				details         ?? "Playing BrenninhoEngine'",
				state,
				smallImageKey,
				smallImageText,
				hasStartTimestamp ?? false,
				endTimestamp      ?? 0,
				partySize         ?? 0,
				partyMax          ?? 0);
		});

		script.set('clearDiscordPresence',  function():Void  { clearPresence(); });
		script.set('resetDiscordClientID',  function():Void  { resetClientID(); });
		script.set('isDiscordInitialized',  function():Bool  { return isInitialized; });
		script.set('discordClientID',       clientID);

		script.set('changeDiscordClientID', function(?newID:String = null):Void
		{
			clientID = newID ?? _defaultID;
		});
	}
	#end

	private static function set_clientID(newID:String):String
	{
		if (newID == null || newID.length == 0) newID = _defaultID;
		var changed:Bool = (clientID != newID);
		clientID = newID;

		if (changed && isInitialized)
		{
			shutdown();
			initialize();
		}

		return newID;
	}

	private static function _threadLoop():Void
	{
		var localID:String = clientID;
		while (_running && localID == clientID)
		{
			#if DISCORD_DISABLE_IO_THREAD
			Discord.UpdateConnection();
			#end
			Discord.RunCallbacks();
			Sys.sleep(0.5);
		}
	}

	private static function _onReady(request:cpp.RawConstPointer<DiscordUser>):Void
	{
		#if (hxdiscord_rpc >= "1.3.0")
		var user:cpp.Star<DiscordUser> = cpp.ConstPointer.fromRaw(request).ptr;
		var username:String            = user.username;
		var discriminator:String       = user.discriminator;
		var globalName:String          = user.globalName ?? username;
		#elseif (hxdiscord_rpc > "1.2.4")
		var user:cpp.Star<DiscordUser> = cpp.ConstPointer.fromRaw(request).ptr;
		var username:String            = cast(user.username, String);
		var discriminator:String       = cast(user.discriminator, String);
		var globalName:String          = username;
		#else
		var user:cpp.Star<DiscordUser> = cpp.ConstPointer.fromRaw(request).ptr;
		var username:String            = cast(user.username, String);
		var discriminator:String       = cast(user.discriminator, String);
		var globalName:String          = username;
		#end

		if (onReady != null) onReady(globalName);
		changePresence();
	}

	private static function _onError(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		var msg:String = cast(message, String);
		if (onError != null) onError(errorCode, msg);
	}

	private static function _onDisconnected(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		var msg:String = cast(message, String);
		isInitialized  = false;
		if (onDisconnect != null) onDisconnect(errorCode, msg);
	}

	private static function _makePresence():DiscordRichPresence
	{
		#if (hxdiscord_rpc >= "1.3.0")
		return new DiscordRichPresence();
		#elseif (hxdiscord_rpc > "1.2.4")
		return new DiscordRichPresence();
		#else
		return DiscordRichPresence.create();
		#end
	}

	private static function _makeHandlers():DiscordEventHandlers
	{
		#if (hxdiscord_rpc >= "1.3.0")
		return new DiscordEventHandlers();
		#elseif (hxdiscord_rpc > "1.2.4")
		return new DiscordEventHandlers();
		#else
		return DiscordEventHandlers.create();
		#end
	}
}