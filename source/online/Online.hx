package online;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Sha256;
import sys.FileSystem;
import sys.io.File;

typedef CloudSaveEntry =
{
	var fileName:String;
	var ?onSuccess:Void->Void;
	var ?onError:String->Void;
	var ?retries:Int;
}

typedef ConnectionStatus =
{
	var connected:Bool;
	var latency:Float;
	var checkedAt:Float;
	var quality:String;
}

typedef OnlineStats =
{
	var totalUploads:Int;
	var totalDownloads:Int;
	var totalSyncs:Int;
	var failedRequests:Int;
	var bytesUploaded:Int;
	var bytesDownloaded:Int;
}

class Online
{
	static final CHECK_URLS:Array<String> = [
		'https://www.google.com',
		'https://www.cloudflare.com',
		'https://www.apple.com'
	];
	static final CLOUD_BASE_URL:String  = 'https://api.brenninhoengine.com/cloud';
	static final SAVE_DIR:String        = 'saves/';
	static final CLOUD_CACHE_DIR:String = 'saves/cloud_cache/';
	static final LOG_DIR:String         = 'logs/';
	static final LOG_FILE:String        = 'logs/online.log';
	static final TIMEOUT:Int            = 10;
	static final RETRY_MAX:Int          = 5;
	static final RETRY_DELAY_MS:Float   = 2000;
	static final STATUS_CACHE_MS:Float  = 5000;
	static final MAX_PENDING:Int        = 50;
	static final MAX_LOG_LINES:Int      = 200;

	public static var isConnected:Bool                   = false;
	public static var isInitialized:Bool                 = false;
	public static var lastStatus:Null<ConnectionStatus>  = null;
	public static var stats:OnlineStats                  = _emptyStats();
	public static var onConnectionChanged:Bool->Void     = null;
	public static var onPendingFlushed:Int->Void         = null;

	private static var _pendingUploads:Array<CloudSaveEntry> = [];
	private static var _userToken:Null<String>  = null;
	private static var _retryTimer:Float        = 0.0;
	private static var _retryCount:Int          = 0;
	private static var _checking:Bool           = false;
	private static var _statusTimer:Float       = 0.0;
	private static var _logBuffer:Array<String> = [];
	private static var _checkUrlIndex:Int       = 0;

	public static function init():Void
	{
		if (isInitialized) return;

		_ensureDir(SAVE_DIR);
		_ensureDir(CLOUD_CACHE_DIR);
		_ensureDir(LOG_DIR);

		isInitialized = true;
		_log('Online system initialized.');

		checkConnection(function(connected:Bool):Void
		{
			if (connected && _pendingUploads.length > 0)
				_flushPendingUploads();
		});
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized) return;

		_statusTimer += elapsed * 1000;
		if (_statusTimer >= STATUS_CACHE_MS)
		{
			_statusTimer = 0.0;
			checkConnection(null);
		}

		if (!isConnected && _retryCount < RETRY_MAX)
		{
			_retryTimer += elapsed * 1000;
			if (_retryTimer >= RETRY_DELAY_MS * Math.min(_retryCount + 1, 4))
			{
				_retryTimer = 0.0;
				_retryCount++;
				_log('Retry attempt $_retryCount / $RETRY_MAX...');
				checkConnection(function(connected:Bool):Void
				{
					if (connected)
					{
						_retryCount = 0;
						_log('Reconnected after $_retryCount retries.');
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

		_checking          = true;
		var startTime:Float = Date.now().getTime();
		var url:String      = CHECK_URLS[_checkUrlIndex % CHECK_URLS.length];

		var http:Http       = new Http(url);
		http.cnxTimeout     = TIMEOUT;

		http.onStatus = function(status:Int):Void
		{
			var latency:Float  = Date.now().getTime() - startTime;
			var connected:Bool = status >= 200 && status < 400;
			if (!connected) _checkUrlIndex = (_checkUrlIndex + 1) % CHECK_URLS.length;
			_handleConnectionResult(connected, latency, callback);
		};

		http.onError = function(_:String):Void
		{
			_checkUrlIndex = (_checkUrlIndex + 1) % CHECK_URLS.length;
			_handleConnectionResult(false, -1, callback);
		};

		try { http.request(false); }
		catch (e:Dynamic) { _handleConnectionResult(false, -1, callback); }
	}

	public static function requireConnection(?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		checkConnection(function(connected:Bool):Void
		{
			if (connected) { if (onSuccess != null) onSuccess(); }
			else            { if (onError  != null) onError('No internet connection. Please check your connection and try again.'); }
		});
	}

	public static function setUserToken(token:String):Void
	{
		_userToken = (token != null && token.length > 0) ? token : null;
		_log('User token ' + (_userToken != null ? 'set.' : 'cleared.'));
	}

	public static function clearUserToken():Void
	{
		_userToken = null;
		_log('User token cleared.');
	}

	public static function uploadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var filePath:String  = SAVE_DIR + fileName;
			if (!FileSystem.exists(filePath))
			{
				if (onError != null) onError('Save file not found: $fileName');
				return;
			}

			var content:String   = File.getContent(filePath);
			var checksum:String  = Sha256.encode(content);
			var cacheFile:String = CLOUD_CACHE_DIR + fileName + '.checksum';

			if (FileSystem.exists(cacheFile) && File.getContent(cacheFile) == checksum)
			{
				_log('Upload skipped — $fileName unchanged.');
				if (onSuccess != null) onSuccess();
				return;
			}

			_doUpload(fileName, content, checksum, onSuccess, onError);
		},
		function(err:String):Void
		{
			_queuePending(fileName, onSuccess, onError);
			if (onError != null) onError(err);
		});
	}

	public static function downloadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var http:Http   = new Http('$CLOUD_BASE_URL/download/$fileName');
			http.cnxTimeout = TIMEOUT;
			_addAuthHeader(http);

			http.onData = function(data:String):Void
			{
				try
				{
					var parsed:Dynamic   = Json.parse(data);
					var content:String   = Reflect.field(parsed, 'content');
					var checksum:String  = Reflect.field(parsed, 'checksum');

					if (content == null || checksum == null)
					{
						if (onError != null) onError('Invalid server response.');
						return;
					}

					if (Sha256.encode(content) != checksum)
					{
						stats.failedRequests++;
						if (onError != null) onError('Checksum mismatch — save may be corrupted.');
						return;
					}

					File.saveContent(SAVE_DIR + fileName, content);
					File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);

					stats.totalDownloads++;
					stats.bytesDownloaded += content.length;
					_log('Downloaded: $fileName (${content.length} bytes)');

					if (onSuccess != null) onSuccess();
				}
				catch (e:Dynamic)
				{
					stats.failedRequests++;
					if (onError != null) onError('Failed to parse server response: $e');
				}
			};

			http.onError = function(msg:String):Void
			{
				stats.failedRequests++;
				_log('Download failed: $fileName — $msg');
				if (onError != null) onError('Download failed: $msg');
			};

			http.request(false);
		},
		onError);
	}

	public static function syncSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var localPath:String  = SAVE_DIR + fileName;
			var cacheFile:String  = CLOUD_CACHE_DIR + fileName + '.checksum';

			if (!FileSystem.exists(localPath))
			{
				_log('Sync: no local file, downloading $fileName...');
				downloadSave(fileName, onSuccess, onError);
				return;
			}

			var localChecksum:String  = Sha256.encode(File.getContent(localPath));
			var cachedChecksum:String = FileSystem.exists(cacheFile) ? File.getContent(cacheFile) : '';

			stats.totalSyncs++;

			if (localChecksum != cachedChecksum)
			{
				_log('Sync: local changes detected, uploading $fileName...');
				uploadSave(fileName, onSuccess, onError);
			}
			else
			{
				_log('Sync: up to date, downloading $fileName...');
				downloadSave(fileName, onSuccess, onError);
			}
		},
		onError);
	}

	public static function deleteSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var http:Http   = new Http('$CLOUD_BASE_URL/delete/$fileName');
			http.cnxTimeout = TIMEOUT;
			_addAuthHeader(http);
			http.addHeader('Content-Type', 'application/json');
			http.setPostData(Json.stringify({fileName: fileName}));

			http.onData = function(_:String):Void
			{
				var cacheFile:String = CLOUD_CACHE_DIR + fileName + '.checksum';
				if (FileSystem.exists(cacheFile)) FileSystem.deleteFile(cacheFile);
				_log('Deleted cloud save: $fileName');
				if (onSuccess != null) onSuccess();
			};

			http.onError = function(msg:String):Void
			{
				stats.failedRequests++;
				if (onError != null) onError('Delete failed: $msg');
			};

			http.request(true);
		},
		onError);
	}

	public static function listCloudSaves(?onSuccess:Array<String>->Void, ?onError:String->Void):Void
	{
		if (!isInitialized) init();

		requireConnection(function():Void
		{
			var http:Http   = new Http('$CLOUD_BASE_URL/list');
			http.cnxTimeout = TIMEOUT;
			_addAuthHeader(http);

			http.onData = function(data:String):Void
			{
				try
				{
					var parsed:Dynamic        = Json.parse(data);
					var files:Array<Dynamic>  = Reflect.field(parsed, 'files');
					var result:Array<String>  = files != null ? files.map((f:Dynamic) -> Std.string(f)) : [];
					if (onSuccess != null) onSuccess(result);
				}
				catch (e:Dynamic)
				{
					if (onError != null) onError('Failed to parse file list: $e');
				}
			};

			http.onError = function(msg:String):Void
			{
				stats.failedRequests++;
				if (onError != null) onError('List failed: $msg');
			};

			http.request(false);
		},
		onError);
	}

	public static function getLatency():Float
	{
		return lastStatus != null ? lastStatus.latency : -1;
	}

	public static function getConnectionQuality():String
	{
		if (lastStatus != null) return lastStatus.quality;
		return 'Offline';
	}

	public static function getStatusText():String
	{
		if (!isConnected) return 'Offline';
		return '${getConnectionQuality()} (${Math.round(getLatency())}ms)';
	}

	public static function getPendingUploads():Array<CloudSaveEntry>
	{
		return _pendingUploads.copy();
	}

	public static function clearPendingUploads():Void
	{
		_log('Pending uploads cleared (${_pendingUploads.length} entries dropped).');
		_pendingUploads = [];
	}

	public static function resetStats():Void
	{
		stats = _emptyStats();
	}

	public static function getLog():Array<String>
	{
		return _logBuffer.copy();
	}

	public static function clearLog():Void
	{
		_logBuffer = [];
	}

	private static function _emptyStats():OnlineStats
	{
		return {
			totalUploads:    0,
			totalDownloads:  0,
			totalSyncs:      0,
			failedRequests:  0,
			bytesUploaded:   0,
			bytesDownloaded: 0
		};
	}

	private static function _ensureDir(path:String):Void
	{
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
	}

	private static function _addAuthHeader(http:Http):Void
	{
		if (_userToken != null)
			http.addHeader('Authorization', 'Bearer $_userToken');
	}

	private static function _queuePending(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (_pendingUploads.length >= MAX_PENDING)
		{
			_log('Pending queue full — dropping oldest entry.');
			_pendingUploads.shift();
		}

		for (entry in _pendingUploads)
			if (entry.fileName == fileName) return;

		_pendingUploads.push({fileName: fileName, onSuccess: onSuccess, onError: onError, retries: 0});
		_log('Queued pending upload: $fileName (${_pendingUploads.length} in queue)');
	}

	private static function _handleConnectionResult(connected:Bool, latency:Float, ?callback:Bool->Void):Void
	{
		_checking = false;

		var wasConnected:Bool = isConnected;
		isConnected = connected;

		lastStatus = {
			connected: connected,
			latency:   latency,
			checkedAt: Date.now().getTime(),
			quality:   _qualityFromLatency(latency)
		};

		if (wasConnected != connected)
		{
			_log('Connection changed: ${connected ? "online" : "offline"} (${latency >= 0 ? Math.round(latency) + "ms" : "N/A"})');
			if (onConnectionChanged != null) onConnectionChanged(connected);
		}

		if (callback != null) callback(connected);
	}

	private static function _qualityFromLatency(latency:Float):String
	{
		if (latency < 0)   return 'Offline';
		if (latency < 100) return 'Excellent';
		if (latency < 300) return 'Good';
		if (latency < 600) return 'Fair';
		return 'Poor';
	}

	private static function _doUpload(fileName:String, content:String, checksum:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		var http:Http   = new Http('$CLOUD_BASE_URL/upload');
		http.cnxTimeout = TIMEOUT;
		_addAuthHeader(http);
		http.addHeader('Content-Type', 'application/json');
		http.setPostData(Json.stringify({
			fileName: fileName,
			content:  content,
			checksum: checksum
		}));

		http.onData = function(_:String):Void
		{
			File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);
			stats.totalUploads++;
			stats.bytesUploaded += content.length;
			_log('Uploaded: $fileName (${content.length} bytes)');
			if (onSuccess != null) onSuccess();
		};

		http.onError = function(msg:String):Void
		{
			stats.failedRequests++;
			_log('Upload failed: $fileName — $msg');
			_queuePending(fileName, onSuccess, onError);
			if (onError != null) onError('Upload failed: $msg');
		};

		http.request(true);
	}

	private static function _flushPendingUploads():Void
	{
		var pending:Array<CloudSaveEntry> = _pendingUploads.copy();
		_pendingUploads = [];

		var flushed:Int = 0;
		for (entry in pending)
		{
			var filePath:String = SAVE_DIR + entry.fileName;
			if (!FileSystem.exists(filePath)) continue;

			var content:String  = File.getContent(filePath);
			var checksum:String = Sha256.encode(content);
			_doUpload(entry.fileName, content, checksum, entry.onSuccess, entry.onError);
			flushed++;
		}

		_log('Flushed $flushed pending upload(s).');
		if (onPendingFlushed != null) onPendingFlushed(flushed);
	}

	private static function _log(msg:String):Void
	{
		var entry:String = '[${Date.now().toString()}] $msg';
		_logBuffer.push(entry);
		if (_logBuffer.length > MAX_LOG_LINES) _logBuffer.shift();

		try
		{
			_ensureDir(LOG_DIR);
			var existing:String = FileSystem.exists(LOG_FILE) ? File.getContent(LOG_FILE) : '';
			var lines:Array<String> = existing.split('\n').filter((l:String) -> l.length > 0);
			lines.push(entry);
			if (lines.length > MAX_LOG_LINES) lines = lines.slice(lines.length - MAX_LOG_LINES);
			File.saveContent(LOG_FILE, lines.join('\n') + '\n');
		}
		catch (e:Dynamic) {}
	}
}
