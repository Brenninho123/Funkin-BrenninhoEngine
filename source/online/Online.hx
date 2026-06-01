package online;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Md5;
import sys.FileSystem;
import sys.io.File;

typedef CloudSaveEntry =
{
	var fileName:String;
	var ?onSuccess:Void->Void;
	var ?onError:String->Void;
}

typedef ConnectionStatus =
{
	var connected:Bool;
	var latency:Float;
	var checkedAt:Float;
}

class Online
{
	static final CHECK_URL:String        = "https://www.google.com";
	static final CLOUD_BASE_URL:String   = "https://api.brenninhoengine.com/cloud";
	static final SAVE_DIR:String         = "saves/";
	static final CLOUD_CACHE_DIR:String  = "saves/cloud_cache/";
	static final TIMEOUT:Int             = 10;
	static final RETRY_MAX:Int           = 3;
	static final RETRY_DELAY_MS:Float    = 2000;
	static final STATUS_CACHE_MS:Float   = 5000;

	public static var isConnected:Bool       = false;
	public static var isInitialized:Bool     = false;
	public static var lastStatus:Null<ConnectionStatus> = null;
	public static var onConnectionChanged:Bool->Void    = null;

	private static var _pendingUploads:Array<CloudSaveEntry> = [];
	private static var _userToken:String     = null;
	private static var _retryTimer:Float     = 0.0;
	private static var _retryCount:Int       = 0;
	private static var _checking:Bool        = false;
	private static var _statusTimer:Float    = 0.0;

	public static function init():Void
	{
		if (isInitialized)
			return;

		if (!FileSystem.exists(SAVE_DIR))
			FileSystem.createDirectory(SAVE_DIR);

		if (!FileSystem.exists(CLOUD_CACHE_DIR))
			FileSystem.createDirectory(CLOUD_CACHE_DIR);

		isInitialized = true;
		checkConnection(function(connected:Bool):Void
		{
			if (connected && _pendingUploads.length > 0)
				_flushPendingUploads();
		});
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized)
			return;

		_statusTimer += elapsed * 1000;

		if (_statusTimer >= STATUS_CACHE_MS)
		{
			_statusTimer = 0.0;
			checkConnection(null);
		}

		if (!isConnected && _retryCount < RETRY_MAX)
		{
			_retryTimer += elapsed * 1000;
			if (_retryTimer >= RETRY_DELAY_MS)
			{
				_retryTimer = 0.0;
				_retryCount++;
				checkConnection(function(connected:Bool):Void
				{
					if (connected)
					{
						_retryCount = 0;
						if (_pendingUploads.length > 0)
							_flushPendingUploads();
					}
				});
			}
		}
	}

	public static function checkConnection(?callback:Bool->Void):Void
	{
		if (_checking)
		{
			if (callback != null) callback(isConnected);
			return;
		}

		if (lastStatus != null && Date.now().getTime() - lastStatus.checkedAt < STATUS_CACHE_MS)
		{
			if (callback != null) callback(isConnected);
			return;
		}

		_checking = true;
		var startTime:Float = Date.now().getTime();

		var http:Http = new Http(CHECK_URL);
		http.cnxTimeout = TIMEOUT;

		http.onStatus = function(status:Int):Void
		{
			var latency:Float  = Date.now().getTime() - startTime;
			var connected:Bool = (status >= 200 && status < 400);
			_handleConnectionResult(connected, latency, callback);
		};

		http.onError = function(_:String):Void
		{
			_handleConnectionResult(false, -1, callback);
		};

		try
		{
			http.request(false);
		}
		catch (e:Dynamic)
		{
			_handleConnectionResult(false, -1, callback);
		}
	}

	public static function requireConnection(?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		checkConnection(function(connected:Bool):Void
		{
			if (connected)
			{
				if (onSuccess != null) onSuccess();
			}
			else
			{
				if (onError != null) onError('No internet connection available. Please check your connection and try again.');
			}
		});
	}

	public static function setUserToken(token:String):Void
	{
		_userToken = token;
	}

	public static function uploadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var filePath:String = SAVE_DIR + fileName;

			if (!FileSystem.exists(filePath))
			{
				if (onError != null) onError('Save file not found: $fileName');
				return;
			}

			var content:String  = File.getContent(filePath);
			var checksum:String = Md5.encode(content);
			var cacheFile:String = CLOUD_CACHE_DIR + fileName + '.checksum';

			if (FileSystem.exists(cacheFile) && File.getContent(cacheFile) == checksum)
			{
				if (onSuccess != null) onSuccess();
				return;
			}

			_doUpload(fileName, content, checksum, onSuccess, onError);
		},
		function(err:String):Void
		{
			_pendingUploads.push({
				fileName:  fileName,
				onSuccess: onSuccess,
				onError:   onError
			});
			if (onError != null) onError(err);
		});
	}

	public static function downloadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var http:Http = new Http('$CLOUD_BASE_URL/download/$fileName');
			http.cnxTimeout = TIMEOUT;

			if (_userToken != null)
				http.addHeader('Authorization', 'Bearer $_userToken');

			http.onData = function(data:String):Void
			{
				try
				{
					var parsed:Dynamic  = Json.parse(data);
					var content:String  = Reflect.field(parsed, 'content');
					var checksum:String = Reflect.field(parsed, 'checksum');

					if (content == null || checksum == null)
					{
						if (onError != null) onError('Invalid response from server.');
						return;
					}

					if (Md5.encode(content) != checksum)
					{
						if (onError != null) onError('Checksum mismatch — save may be corrupted.');
						return;
					}

					File.saveContent(SAVE_DIR + fileName, content);
					File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);

					if (onSuccess != null) onSuccess();
				}
				catch (e:Dynamic)
				{
					if (onError != null) onError('Failed to parse server response: $e');
				}
			};

			http.onError = function(msg:String):Void
			{
				if (onError != null) onError('Download failed: $msg');
			};

			http.request(false);
		},
		onError);
	}

	public static function syncSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		requireConnection(function():Void
		{
			var localPath:String  = SAVE_DIR + fileName;
			var cacheFile:String  = CLOUD_CACHE_DIR + fileName + '.checksum';

			if (!FileSystem.exists(localPath))
			{
				downloadSave(fileName, onSuccess, onError);
				return;
			}

			var localChecksum:String  = Md5.encode(File.getContent(localPath));
			var cachedChecksum:String = FileSystem.exists(cacheFile) ? File.getContent(cacheFile) : '';

			if (localChecksum != cachedChecksum)
				uploadSave(fileName, onSuccess, onError);
			else
				downloadSave(fileName, onSuccess, onError);
		},
		onError);
	}

	public static function getLatency():Float
	{
		return lastStatus != null ? lastStatus.latency : -1;
	}

	public static function getConnectionQuality():String
	{
		var latency:Float = getLatency();
		if (latency < 0)    return 'Offline';
		if (latency < 100)  return 'Excellent';
		if (latency < 300)  return 'Good';
		if (latency < 600)  return 'Fair';
		return 'Poor';
	}

	public static function getPendingUploads():Array<CloudSaveEntry>
	{
		return _pendingUploads.copy();
	}

	public static function clearPendingUploads():Void
	{
		_pendingUploads = [];
	}

	private static function _handleConnectionResult(connected:Bool, latency:Float, ?callback:Bool->Void):Void
	{
		_checking = false;

		var wasConnected:Bool = isConnected;
		isConnected = connected;

		lastStatus = {
			connected:  connected,
			latency:    latency,
			checkedAt:  Date.now().getTime()
		};

		if (wasConnected != connected && onConnectionChanged != null)
			onConnectionChanged(connected);

		if (callback != null)
			callback(connected);
	}

	private static function _doUpload(fileName:String, content:String, checksum:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		var http:Http = new Http('$CLOUD_BASE_URL/upload');
		http.cnxTimeout = TIMEOUT;

		if (_userToken != null)
			http.addHeader('Authorization', 'Bearer $_userToken');

		http.addHeader('Content-Type', 'application/json');
		http.setPostData(Json.stringify({
			fileName: fileName,
			content:  content,
			checksum: checksum
		}));

		http.onData = function(_:String):Void
		{
			File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);
			if (onSuccess != null) onSuccess();
		};

		http.onError = function(msg:String):Void
		{
			_pendingUploads.push({
				fileName:  fileName,
				onSuccess: onSuccess,
				onError:   onError
			});
			if (onError != null) onError('Upload failed: $msg');
		};

		http.request(true);
	}

	private static function _flushPendingUploads():Void
	{
		var pending:Array<CloudSaveEntry> = _pendingUploads.copy();
		_pendingUploads = [];

		for (entry in pending)
		{
			var filePath:String = SAVE_DIR + entry.fileName;
			if (!FileSystem.exists(filePath)) continue;

			var content:String  = File.getContent(filePath);
			var checksum:String = Md5.encode(content);
			_doUpload(entry.fileName, content, checksum, entry.onSuccess, entry.onError);
		}
	}
}