package online;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Md5;
import sys.FileSystem;
import sys.io.File;

class Online
{
	static final CHECK_URL:String        = "https://www.google.com";
	static final CLOUD_BASE_URL:String   = "https://api.brenninhoengine.com/cloud";
	static final SAVE_DIR:String         = "saves/";
	static final CLOUD_CACHE_DIR:String  = "saves/cloud_cache/";
	static final TIMEOUT:Int             = 10;

	public static var isConnected:Bool   = false;
	public static var isInitialized:Bool = false;

	private static var _pendingUploads:Array<CloudSaveEntry> = [];
	private static var _userToken:String = null;

	public static function init():Void
	{
		if (isInitialized)
			return;

		if (!FileSystem.exists(SAVE_DIR))
			FileSystem.createDirectory(SAVE_DIR);

		if (!FileSystem.exists(CLOUD_CACHE_DIR))
			FileSystem.createDirectory(CLOUD_CACHE_DIR);

		isInitialized = true;
		checkConnection(null);
	}

	public static function checkConnection(?callback:Bool->Void):Void
	{
		var http:Http = new Http(CHECK_URL);
		http.cnxTimeout = TIMEOUT;

		http.onStatus = function(status:Int):Void
		{
			isConnected = (status >= 200 && status < 400);
			if (callback != null)
				callback(isConnected);

			if (isConnected && _pendingUploads.length > 0)
				_flushPendingUploads();
		};

		http.onError = function(msg:String):Void
		{
			isConnected = false;
			if (callback != null)
				callback(false);
		};

		try
		{
			http.request(false);
		}
		catch (e:Dynamic)
		{
			isConnected = false;
			if (callback != null)
				callback(false);
		}
	}

	public static function setUserToken(token:String):Void
	{
		_userToken = token;
	}

	public static function uploadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized)
			init();

		var filePath:String = SAVE_DIR + fileName;

		if (!FileSystem.exists(filePath))
		{
			if (onError != null)
				onError('Save file not found: $fileName');
			return;
		}

		var content:String  = File.getContent(filePath);
		var checksum:String = Md5.encode(content);

		var cacheFile:String = CLOUD_CACHE_DIR + fileName + '.checksum';
		if (FileSystem.exists(cacheFile) && File.getContent(cacheFile) == checksum)
		{
			if (onSuccess != null)
				onSuccess();
			return;
		}

		if (!isConnected)
		{
			_pendingUploads.push({
				fileName: fileName,
				onSuccess: onSuccess,
				onError: onError
			});
			return;
		}

		_doUpload(fileName, content, checksum, onSuccess, onError);
	}

	public static function downloadSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		if (!isInitialized)
			init();

		if (!isConnected)
		{
			if (onError != null)
				onError('No internet connection available.');
			return;
		}

		var http:Http = new Http('$CLOUD_BASE_URL/download/$fileName');
		http.cnxTimeout = TIMEOUT;

		if (_userToken != null)
			http.addHeader('Authorization', 'Bearer $_userToken');

		http.onData = function(data:String):Void
		{
			try
			{
				var parsed:Dynamic = Json.parse(data);
				var content:String = Reflect.field(parsed, 'content');
				var checksum:String = Reflect.field(parsed, 'checksum');

				if (content == null || checksum == null)
				{
					if (onError != null)
						onError('Invalid response from server.');
					return;
				}

				if (Md5.encode(content) != checksum)
				{
					if (onError != null)
						onError('Checksum mismatch — save may be corrupted.');
					return;
				}

				File.saveContent(SAVE_DIR + fileName, content);
				File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);

				if (onSuccess != null)
					onSuccess();
			}
			catch (e:Dynamic)
			{
				if (onError != null)
					onError('Failed to parse server response: $e');
			}
		};

		http.onError = function(msg:String):Void
		{
			if (onError != null)
				onError('Download failed: $msg');
		};

		http.request(false);
	}

	public static function syncSave(fileName:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		checkConnection(function(connected:Bool):Void
		{
			if (!connected)
			{
				if (onError != null)
					onError('No internet connection available.');
				return;
			}

			var localPath:String = SAVE_DIR + fileName;
			var cacheFile:String = CLOUD_CACHE_DIR + fileName + '.checksum';

			if (!FileSystem.exists(localPath))
			{
				downloadSave(fileName, onSuccess, onError);
				return;
			}

			var localChecksum:String = Md5.encode(File.getContent(localPath));
			var cachedChecksum:String = FileSystem.exists(cacheFile) ? File.getContent(cacheFile) : '';

			if (localChecksum != cachedChecksum)
				uploadSave(fileName, onSuccess, onError);
			else
				downloadSave(fileName, onSuccess, onError);
		});
	}

	public static function getPendingUploads():Array<CloudSaveEntry>
	{
		return _pendingUploads.copy();
	}

	public static function clearPendingUploads():Void
	{
		_pendingUploads = [];
	}

	private static function _doUpload(fileName:String, content:String, checksum:String, ?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		var http:Http = new Http('$CLOUD_BASE_URL/upload');
		http.cnxTimeout = TIMEOUT;

		if (_userToken != null)
			http.addHeader('Authorization', 'Bearer $_userToken');

		http.addHeader('Content-Type', 'application/json');

		var payload:String = Json.stringify({
			fileName: fileName,
			content:  content,
			checksum: checksum
		});

		http.setPostData(payload);

		http.onData = function(data:String):Void
		{
			File.saveContent(CLOUD_CACHE_DIR + fileName + '.checksum', checksum);
			if (onSuccess != null)
				onSuccess();
		};

		http.onError = function(msg:String):Void
		{
			_pendingUploads.push({
				fileName: fileName,
				onSuccess: onSuccess,
				onError: onError
			});
			if (onError != null)
				onError('Upload failed: $msg');
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
			if (!FileSystem.exists(filePath))
				continue;

			var content:String  = File.getContent(filePath);
			var checksum:String = Md5.encode(content);
			_doUpload(entry.fileName, content, checksum, entry.onSuccess, entry.onError);
		}
	}
}

typedef CloudSaveEntry =
{
	var fileName:String;
	var ?onSuccess:Void->Void;
	var ?onError:String->Void;
}
