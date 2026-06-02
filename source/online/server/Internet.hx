package online.server;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Sha256;
import sys.FileSystem;
import sys.io.File;

typedef InternetStatus =
{
	var connected:Bool;
	var latency:Float;
	var quality:String;
	var checkedAt:Float;
}

typedef HttpResponse =
{
	var success:Bool;
	var status:Int;
	var data:String;
	var error:String;
	var latency:Float;
}

typedef RequestOptions =
{
	var ?headers:Map<String, String>;
	var ?timeout:Int;
	var ?retries:Int;
	var ?retryDelay:Float;
}

class Internet
{
	static final CHECK_URLS:Array<String> = [
		"https://www.google.com",
		"https://www.cloudflare.com",
		"https://www.apple.com"
	];

	static final DEFAULT_TIMEOUT:Int       = 10;
	static final DEFAULT_RETRIES:Int       = 2;
	static final DEFAULT_RETRY_DELAY:Float = 1.0;
	static final STATUS_CACHE_MS:Float     = 5000;
	static final LOG_PATH:String           = "logs/internet.log";
	static final MAX_LOG_ENTRIES:Int       = 100;

	public static var isInitialized:Bool              = false;
	public static var lastStatus:Null<InternetStatus> = null;
	public static var onStatusChanged:Bool->Void      = null;
	public static var onRequestComplete:HttpResponse->Void = null;
	public static var onRequestFailed:String->Void    = null;

	private static var _requestLog:Array<String>      = [];
	private static var _requestCount:Int              = 0;
	private static var _failCount:Int                 = 0;
	private static var _totalLatency:Float            = 0.0;
	private static var _checking:Bool                 = false;
	private static var _retryTimer:Float              = 0.0;
	private static var _retryCount:Int                = 0;
	private static final MAX_RETRIES:Int              = 3;
	private static final RETRY_DELAY_MS:Float         = 2000;

	public static function init():Void
	{
		if (isInitialized) return;

		if (!FileSystem.exists('logs'))
			FileSystem.createDirectory('logs');

		isInitialized = true;
		_log('Internet system initialized');

		check(null);
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized) return;

		if (lastStatus != null && !lastStatus.connected)
		{
			_retryTimer += elapsed * 1000;
			if (_retryTimer >= RETRY_DELAY_MS && _retryCount < MAX_RETRIES)
			{
				_retryTimer = 0.0;
				_retryCount++;
				check(function(connected:Bool):Void
				{
					if (connected) _retryCount = 0;
				});
			}
		}
		else
		{
			_retryTimer = 0.0;
		}
	}

	public static function check(?callback:Bool->Void):Void
	{
		if (_checking)
		{
			if (callback != null) callback(lastStatus != null ? lastStatus.connected : false);
			return;
		}

		if (lastStatus != null && Date.now().getTime() - lastStatus.checkedAt < STATUS_CACHE_MS)
		{
			if (callback != null) callback(lastStatus.connected);
			return;
		}

		_checking = true;

		var checked:Int    = 0;
		var success:Bool   = false;
		var bestLatency:Float = -1;

		for (url in CHECK_URLS)
		{
			var start:Float = Date.now().getTime();
			var http:Http   = new Http(url);
			http.cnxTimeout = 5;

			http.onStatus = function(status:Int):Void
			{
				if (status >= 200 && status < 400)
				{
					var latency:Float = Date.now().getTime() - start;
					if (bestLatency < 0 || latency < bestLatency)
						bestLatency = latency;
					success = true;
				}
				checked++;
				if (checked >= CHECK_URLS.length)
					_finalizeCheck(success, bestLatency, callback);
			};

			http.onError = function(_:String):Void
			{
				checked++;
				if (checked >= CHECK_URLS.length)
					_finalizeCheck(success, bestLatency, callback);
			};

			try { http.request(false); }
			catch (e:Dynamic)
			{
				checked++;
				if (checked >= CHECK_URLS.length)
					_finalizeCheck(success, bestLatency, callback);
			}
		}
	}

	public static function get(url:String, ?options:RequestOptions, ?callback:HttpResponse->Void):Void
	{
		if (!isInitialized) init();
		_doRequest(url, 'GET', null, options, callback);
	}

	public static function post(url:String, data:String, ?options:RequestOptions, ?callback:HttpResponse->Void):Void
	{
		if (!isInitialized) init();
		_doRequest(url, 'POST', data, options, callback);
	}

	public static function getJson(url:String, ?options:RequestOptions, ?callback:Dynamic->Void):Void
	{
		get(url, options, function(response:HttpResponse):Void
		{
			if (!response.success)
			{
				if (callback != null) callback(null);
				return;
			}
			try
			{
				var parsed:Dynamic = Json.parse(response.data);
				if (callback != null) callback(parsed);
			}
			catch (e:Dynamic)
			{
				if (callback != null) callback(null);
			}
		});
	}

	public static function postJson(url:String, payload:Dynamic, ?options:RequestOptions, ?callback:HttpResponse->Void):Void
	{
		var headers:Map<String, String> = new Map();
		headers.set('Content-Type', 'application/json');

		if (options == null) options = {};
		if (options.headers == null) options.headers = headers;
		else options.headers.set('Content-Type', 'application/json');

		post(url, Json.stringify(payload), options, callback);
	}

	public static function download(url:String, savePath:String, ?callback:Bool->Void):Void
	{
		if (!isInitialized) init();

		check(function(connected:Bool):Void
		{
			if (!connected)
			{
				_log('Download failed — no connection: $url');
				if (callback != null) callback(false);
				return;
			}

			var http:Http = new Http(url);
			http.cnxTimeout = 30;

			http.onBytes = function(bytes:haxe.io.Bytes):Void
			{
				try
				{
					var dir:String = haxe.io.Path.directory(savePath);
					if (dir.length > 0 && !FileSystem.exists(dir))
						FileSystem.createDirectory(dir);
					File.saveBytes(savePath, bytes);
					_log('Downloaded: $url -> $savePath (${bytes.length} bytes)');
					if (callback != null) callback(true);
				}
				catch (e:Dynamic)
				{
					_log('Failed to save download: $url — $e');
					if (callback != null) callback(false);
				}
			};

			http.onError = function(err:String):Void
			{
				_log('Download error: $url — $err');
				if (callback != null) callback(false);
			};

			try { http.request(false); }
			catch (e:Dynamic)
			{
				_log('Download exception: $url — $e');
				if (callback != null) callback(false);
			}
		});
	}

	public static function isConnected():Bool
	{
		return lastStatus != null && lastStatus.connected;
	}

	public static function getLatency():Float
	{
		return lastStatus != null ? lastStatus.latency : -1;
	}

	public static function getQuality():String
	{
		if (lastStatus == null || !lastStatus.connected) return 'Offline';
		return lastStatus.quality;
	}

	public static function getAverageLatency():Float
	{
		if (_requestCount == 0) return -1;
		return _totalLatency / _requestCount;
	}

	public static function getRequestCount():Int
	{
		return _requestCount;
	}

	public static function getFailCount():Int
	{
		return _failCount;
	}

	public static function getSuccessRate():Float
	{
		if (_requestCount == 0) return 0.0;
		return (_requestCount - _failCount) / _requestCount;
	}

	public static function getStatusText():String
	{
		if (lastStatus == null) return 'Unknown';
		if (!lastStatus.connected) return 'Offline';
		return '${lastStatus.quality} (${Math.round(lastStatus.latency)}ms)';
	}

	public static function getLog(?limit:Int = 50):Array<String>
	{
		var copy:Array<String> = _requestLog.copy();
		copy.reverse();
		return copy.slice(0, limit);
	}

	public static function clearLog():Void
	{
		_requestLog = [];
	}

	public static function requireConnection(?onSuccess:Void->Void, ?onError:String->Void):Void
	{
		check(function(connected:Bool):Void
		{
			if (connected)
			{
				if (onSuccess != null) onSuccess();
			}
			else
			{
				var msg:String = 'No internet connection available.';
				if (onError != null) onError(msg);
			}
		});
	}

	public static function buildUrl(base:String, ?params:Map<String, String>):String
	{
		if (params == null || params.keys().hasNext() == false) return base;
		var parts:Array<String> = [];
		for (key => value in params)
			parts.push('$key=${StringTools.urlEncode(value)}');
		return base + '?' + parts.join('&');
	}

	public static function flushLog():Void
	{
		if (_requestLog.length == 0) return;
		try
		{
			var existing:String = FileSystem.exists(LOG_PATH) ? File.getContent(LOG_PATH) : '';
			File.saveContent(LOG_PATH, existing + _requestLog.join('\n') + '\n');
			_requestLog = [];
		}
		catch (e:Dynamic) {}
	}

	private static function _doRequest(url:String, method:String, ?postData:String, ?options:RequestOptions, ?callback:HttpResponse->Void):Void
	{
		var timeout:Int    = options?.timeout ?? DEFAULT_TIMEOUT;
		var retries:Int    = options?.retries ?? DEFAULT_RETRIES;
		var headers        = options?.headers;

		_requestCount++;
		var start:Float    = Date.now().getTime();
		var attempts:Int   = 0;

		function attempt():Void
		{
			attempts++;
			var http:Http = new Http(url);
			http.cnxTimeout = timeout;

			if (headers != null)
				for (key => value in headers)
					http.addHeader(key, value);

			if (postData != null)
				http.setPostData(postData);

			http.onData = function(data:String):Void
			{
				var latency:Float = Date.now().getTime() - start;
				_totalLatency += latency;

				var response:HttpResponse = {
					success: true,
					status:  200,
					data:    data,
					error:   '',
					latency: latency
				};

				_log('$method $url — ${Math.round(latency)}ms');

				if (onRequestComplete != null) onRequestComplete(response);
				if (callback != null) callback(response);
			};

			http.onStatus = function(status:Int):Void
			{
				if (status >= 400)
					_log('$method $url — HTTP $status');
			};

			http.onError = function(err:String):Void
			{
				if (attempts <= retries)
				{
					Sys.sleep(options?.retryDelay ?? DEFAULT_RETRY_DELAY);
					attempt();
					return;
				}

				_failCount++;
				var latency:Float = Date.now().getTime() - start;

				var response:HttpResponse = {
					success: false,
					status:  0,
					data:    '',
					error:   err,
					latency: latency
				};

				_log('$method $url — FAILED: $err (after $attempts attempts)');

				if (onRequestFailed != null) onRequestFailed(err);
				if (callback != null) callback(response);
			};

			try
			{
				http.request(method == 'POST');
			}
			catch (e:Dynamic)
			{
				if (attempts <= retries)
				{
					attempt();
					return;
				}

				_failCount++;
				var response:HttpResponse = {
					success: false,
					status:  0,
					data:    '',
					error:   Std.string(e),
					latency: Date.now().getTime() - start
				};

				if (callback != null) callback(response);
			}
		}

		attempt();
	}

	private static function _finalizeCheck(connected:Bool, latency:Float, ?callback:Bool->Void):Void
	{
		_checking = false;

		var wasConnected:Bool = lastStatus != null ? lastStatus.connected : true;

		lastStatus = {
			connected:  connected,
			latency:    latency,
			quality:    _qualityFromLatency(latency),
			checkedAt:  Date.now().getTime()
		};

		if (wasConnected != connected)
		{
			_log('Connection changed: ${connected ? "Online" : "Offline"}');
			if (onStatusChanged != null) onStatusChanged(connected);
		}

		if (callback != null) callback(connected);

		if (_requestLog.length >= MAX_LOG_ENTRIES) flushLog();
	}

	private static function _qualityFromLatency(latency:Float):String
	{
		if (latency < 0)    return 'Offline';
		if (latency < 80)   return 'Excellent';
		if (latency < 200)  return 'Good';
		if (latency < 500)  return 'Fair';
		return 'Poor';
	}

	private static function _log(message:String):Void
	{
		var line:String = '[${DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S")}] $message';
		_requestLog.push(line);
		if (_requestLog.length >= MAX_LOG_ENTRIES) flushLog();
	}
}