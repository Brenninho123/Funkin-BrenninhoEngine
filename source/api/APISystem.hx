package api;

import haxe.crypto.Md5;
import haxe.crypto.Sha256;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

class APISystem
{
	static final BLOCKED_FUNCTIONS:Array<String> = [
		"Sys.command",
		"Sys.exit",
		"Sys.setCwd",
		"Sys.getEnv",
		"Sys.putEnv",
		"File.saveContent",
		"File.getContent",
		"FileSystem.deleteFile",
		"FileSystem.deleteDirectory",
		"FileSystem.createDirectory",
		"Process.new",
		"cpp.Lib.command",
		"cpp.Lib.load",
		"Reflect.callMethod",
		"Type.createInstance",
		"Type.resolveClass",
		"Type.resolveEnum",
		"untyped",
		"__js__",
		"__lua__",
		"__cpp__",
		"__python__",
		"__cs__",
		"__java__",
		"haxe.macro",
		"sys.net.Socket",
		"sys.net.Host",
		"sys.ssl.Socket",
		"openfl.Lib.getURL",
	];

	static final ALLOWED_MOD_FIELDS:Array<String> = [
		"name",
		"description",
		"version",
		"author",
		"color",
		"icon",
		"restart",
		"discordRPC",
		"playableCharacter",
		"opponent",
		"girlfriend",
		"stage",
		"titleState",
		"runsAfterMods"
	];

	static final DANGEROUS_EXTENSIONS:Array<String> = [
		".exe", ".bat", ".sh", ".cmd", ".ps1",
		".dll", ".so", ".dylib", ".bin",
		".py", ".rb", ".pl", ".php"
	];

	static final RATE_WINDOW_MS:Float   = 1000;
	static final MAX_CALLS_PER_SEC:Int  = 120;
	static final BURST_LIMIT:Int        = 200;
	static final BLOCK_DURATION_MS:Float = 5000;
	static final LOG_PATH:String        = "logs/api.log";
	static final SUSPICIOUS_LIMIT:Int   = 3;

	public static var isInitialized:Bool = false;
	public static var onThreatDetected:String->Void = null;

	private static var _callLog:Array<APILogEntry>          = [];
	private static var _authenticatedMods:Map<String, Bool> = new Map();
	private static var _blockedCalls:Map<String, Int>       = new Map();
	private static var _rateCounts:Map<String, Array<Float>> = new Map();
	private static var _blockedUntil:Map<String, Float>     = new Map();
	private static var _suspicionScore:Map<String, Int>     = new Map();
	private static var _sessionToken:String                 = '';
	private static var _callHistory:Array<CallRecord>       = [];
	private static var _trustedMods:Array<String>           = [];
	private static var _sandboxMode:Bool                    = false;

	public static function init():Void
	{
		if (isInitialized) return;

		if (!FileSystem.exists('logs'))
			FileSystem.createDirectory('logs');

		_sessionToken = _generateToken();
		isInitialized = true;

		_log('APISystem initialized with token ${_sessionToken.substr(0, 8)}...', INFO);
	}

	public static function isCallBlocked(funcName:String, ?caller:String = 'unknown'):Bool
	{
		if (!isInitialized) init();

		if (_isTemporarilyBlocked(caller))
		{
			_log('Temporarily blocked call from $caller: $funcName', THREAT);
			return true;
		}

		var blocked:Bool = BLOCKED_FUNCTIONS.contains(funcName)
			|| _containsDangerousPattern(funcName);

		if (blocked)
		{
			_recordBlockedCall(funcName, caller);
			_log('Blocked call: $funcName from $caller', THREAT);

			if (onThreatDetected != null)
				onThreatDetected('Blocked dangerous call: $funcName from $caller');
		}

		return blocked;
	}

	public static function checkRateLimit(caller:String):Bool
	{
		if (!isInitialized) init();

		var now:Float = Date.now().getTime();

		if (!_rateCounts.exists(caller))
			_rateCounts.set(caller, []);

		var calls:Array<Float> = _rateCounts.get(caller);
		while (calls.length > 0 && calls[0] < now - RATE_WINDOW_MS)
			calls.shift();

		if (calls.length >= BURST_LIMIT)
		{
			_blockTemporarily(caller);
			_log('Burst limit exceeded by $caller — blocked for ${BLOCK_DURATION_MS}ms', THREAT);
			return false;
		}

		if (calls.length >= MAX_CALLS_PER_SEC)
		{
			_incrementSuspicion(caller, 'Rate limit exceeded');
			_log('Rate limit exceeded by $caller', WARNING);
			return false;
		}

		calls.push(now);
		return true;
	}

	public static function authenticateMod(modDirectory:String):Bool
	{
		if (!isInitialized) init();

		if (_authenticatedMods.exists(modDirectory))
			return _authenticatedMods.get(modDirectory);

		if (_trustedMods.contains(modDirectory))
		{
			_authenticatedMods.set(modDirectory, true);
			return true;
		}

		var packPath:String = haxe.io.Path.join([modDirectory, 'pack.json']);

		if (!FileSystem.exists(packPath))
		{
			_log('Mod auth failed — no pack.json: $modDirectory', WARNING);
			_authenticatedMods.set(modDirectory, false);
			return false;
		}

		try
		{
			var content:String = File.getContent(packPath);
			var pack:Dynamic   = Json.parse(content);

			if (!_validateModPack(pack, modDirectory))
			{
				_authenticatedMods.set(modDirectory, false);
				return false;
			}

			if (_containsMaliciousContent(content))
			{
				_log('Mod pack contains malicious content: $modDirectory', THREAT);
				_authenticatedMods.set(modDirectory, false);
				if (onThreatDetected != null)
					onThreatDetected('Malicious mod pack detected: $modDirectory');
				return false;
			}

			var checksum:String = Sha256.encode(content);
			_log('Mod authenticated: $modDirectory (sha256: ${checksum.substr(0, 16)}...)', INFO);
			_authenticatedMods.set(modDirectory, true);
			return true;
		}
		catch (e:Dynamic)
		{
			_log('Mod auth error: $modDirectory — $e', ERROR);
			_authenticatedMods.set(modDirectory, false);
			return false;
		}
	}

	public static function validateFilePath(path:String, ?allowExternal:Bool = false):Bool
	{
		if (path == null || path.length == 0) return false;

		var normalized:String = path.replace('\\', '/').toLowerCase();

		if (normalized.contains('..') || normalized.contains('\0') || normalized.contains('//'))
		{
			_log('Path traversal attempt: $path', THREAT);
			if (onThreatDetected != null) onThreatDetected('Path traversal: $path');
			return false;
		}

		for (ext in DANGEROUS_EXTENSIONS)
			if (normalized.endsWith(ext))
			{
				_log('Dangerous file extension blocked: $path', THREAT);
				return false;
			}

		if (!allowExternal)
		{
			var trusted:Bool = false;
			for (p in ['assets/', 'mods/', 'saves/', 'export/'])
				if (normalized.startsWith(p)) { trusted = true; break; }

			if (!trusted)
			{
				_log('Untrusted path blocked: $path', WARNING);
				return false;
			}
		}

		return true;
	}

	public static function validateInput(input:String, ?maxLength:Int = 256):InputValidation
	{
		if (input == null)
			return { valid: false, reason: 'Input is null', sanitized: '' };

		if (input.length > maxLength)
			return { valid: false, reason: 'Input exceeds max length ($maxLength)', sanitized: input.substr(0, maxLength) };

		var sanitized:String = input
			.replace('<', '&lt;')
			.replace('>', '&gt;')
			.replace('"', '&quot;')
			.replace("'", '&#39;')
			.replace('\0', '');

		for (pattern in BLOCKED_FUNCTIONS)
			if (sanitized.contains(pattern))
				return { valid: false, reason: 'Dangerous pattern in input: $pattern', sanitized: sanitized };

		return { valid: true, reason: '', sanitized: sanitized };
	}

	public static function signPayload(data:String):String
	{
		return Sha256.encode(data + _sessionToken);
	}

	public static function verifyPayload(data:String, signature:String):Bool
	{
		return signPayload(data) == signature;
	}

	public static function trustMod(modDirectory:String):Void
	{
		if (!_trustedMods.contains(modDirectory))
		{
			_trustedMods.push(modDirectory);
			_log('Mod trusted: $modDirectory', INFO);
		}
	}

	public static function untrustMod(modDirectory:String):Void
	{
		_trustedMods.remove(modDirectory);
		_authenticatedMods.remove(modDirectory);
		_log('Mod untrusted: $modDirectory', INFO);
	}

	public static function enableSandbox():Void
	{
		_sandboxMode = true;
		_log('Sandbox mode enabled', SYSTEM);
	}

	public static function disableSandbox():Void
	{
		_sandboxMode = false;
		_log('Sandbox mode disabled', SYSTEM);
	}

	public static function isSandboxed():Bool
	{
		return _sandboxMode;
	}

	public static function getBlockedCallReport():Map<String, Int>
	{
		return _blockedCalls.copy();
	}

	public static function getSuspicionScore(caller:String):Int
	{
		return _suspicionScore.exists(caller) ? _suspicionScore.get(caller) : 0;
	}

	public static function getCallHistory(?limit:Int = 50):Array<CallRecord>
	{
		var copy:Array<CallRecord> = _callHistory.copy();
		copy.reverse();
		return copy.slice(0, limit);
	}

	public static function getSecuritySummary():SecuritySummary
	{
		var threats:Int  = 0;
		var warnings:Int = 0;

		for (entry in _callLog)
		{
			if (entry.level == 'THREAT')  threats++;
			if (entry.level == 'WARNING') warnings++;
		}

		var highRisk:Array<String> = [];
		for (id => score in _suspicionScore)
			if (score >= SUSPICIOUS_LIMIT) highRisk.push(id);

		return {
			threats:          threats,
			warnings:         warnings,
			blockedCalls:     [for (k => v in _blockedCalls) '$k: $v'],
			highRiskCallers:  highRisk,
			authenticatedMods: [for (k => v in _authenticatedMods) if (v) k],
			sandboxMode:      _sandboxMode,
			sessionToken:     _sessionToken.substr(0, 8) + '...'
		};
	}

	public static function clearModCache():Void
	{
		_authenticatedMods.clear();
		_log('Mod authentication cache cleared', SYSTEM);
	}

	public static function flushLog():Void
	{
		if (!isInitialized || _callLog.length == 0) return;

		try
		{
			var lines:Array<String> = _callLog.map((e:APILogEntry) ->
				'[${e.timestamp}] [${e.level}] ${e.message}'
			);
			var existing:String = FileSystem.exists(LOG_PATH) ? File.getContent(LOG_PATH) : '';
			File.saveContent(LOG_PATH, existing + lines.join('\n') + '\n');
			_callLog = [];
		}
		catch (e:Dynamic) {}
	}

	public static function logCall(funcName:String, ?args:Array<Dynamic>, ?caller:String = 'unknown'):Void
	{
		if (!isInitialized) return;

		var argStr:String = args != null && args.length > 0
			? args.map((a:Dynamic) -> Std.string(a)).join(', ')
			: 'none';

		_callHistory.push({
			func:      funcName,
			caller:    caller,
			args:      argStr,
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		});

		if (_callHistory.length > 200)
			_callHistory.shift();

		_log('Call: $funcName($argStr) by $caller', INFO);
	}

	private static function _validateModPack(pack:Dynamic, modDir:String):Bool
	{
		if (pack == null) return false;
		if (Reflect.field(pack, 'name') == null)
		{
			_log('Mod pack missing name field: $modDir', WARNING);
			return false;
		}

		for (field in Reflect.fields(pack))
		{
			if (!ALLOWED_MOD_FIELDS.contains(field))
			{
				_log('Suspicious field "$field" in pack.json: $modDir', WARNING);
				_incrementSuspicion(modDir, 'Suspicious pack field: $field');
				return false;
			}
		}

		return true;
	}

	private static function _containsMaliciousContent(content:String):Bool
	{
		for (pattern in BLOCKED_FUNCTIONS)
			if (content.contains(pattern)) return true;

		for (ext in DANGEROUS_EXTENSIONS)
			if (content.contains(ext)) return true;

		return false;
	}

	private static function _containsDangerousPattern(funcName:String):Bool
	{
		var lower:String = funcName.toLowerCase();
		return lower.contains('exec')
			|| lower.contains('shell')
			|| lower.contains('spawn')
			|| lower.contains('inject')
			|| lower.contains('overflow')
			|| lower.contains('exploit');
	}

	private static function _recordBlockedCall(funcName:String, caller:String):Void
	{
		var count:Int = _blockedCalls.exists(funcName) ? _blockedCalls.get(funcName) : 0;
		_blockedCalls.set(funcName, count + 1);
		_incrementSuspicion(caller, 'Blocked call: $funcName');
	}

	private static function _incrementSuspicion(caller:String, reason:String):Void
	{
		var score:Int = _suspicionScore.exists(caller) ? _suspicionScore.get(caller) : 0;
		score++;
		_suspicionScore.set(caller, score);

		if (score >= SUSPICIOUS_LIMIT)
		{
			_blockTemporarily(caller);
			_log('High suspicion — auto-blocked: $caller ($reason)', THREAT);
			if (onThreatDetected != null)
				onThreatDetected('Suspicious caller blocked: $caller — $reason');
		}
		else
		{
			_log('Suspicion +1 for $caller: $reason (score: $score)', WARNING);
		}
	}

	private static function _blockTemporarily(caller:String):Void
	{
		_blockedUntil.set(caller, Date.now().getTime() + BLOCK_DURATION_MS);
		_log('Temporarily blocked: $caller for ${BLOCK_DURATION_MS}ms', THREAT);
	}

	private static function _isTemporarilyBlocked(caller:String):Bool
	{
		if (!_blockedUntil.exists(caller)) return false;
		if (Date.now().getTime() > _blockedUntil.get(caller))
		{
			_blockedUntil.remove(caller);
			return false;
		}
		return true;
	}

	private static function _generateToken():String
	{
		var seed:String = Std.string(Date.now().getTime())
			+ Std.string(Math.random())
			+ backend.system.Main.platform
			+ states.MainMenuState.psychEngineVersion;
		return Sha256.encode(seed);
	}

	private static function _log(message:String, level:APILogLevel):Void
	{
		var entry:APILogEntry = {
			message:   message,
			level:     Std.string(level),
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		};
		_callLog.push(entry);
		if (_callLog.length >= 100) flushLog();
	}
}

enum APILogLevel
{
	INFO;
	WARNING;
	ERROR;
	THREAT;
	SYSTEM;
}

typedef APILogEntry =
{
	var message:String;
	var level:String;
	var timestamp:String;
}

typedef CallRecord =
{
	var func:String;
	var caller:String;
	var args:String;
	var timestamp:String;
}

typedef InputValidation =
{
	var valid:Bool;
	var reason:String;
	var sanitized:String;
}

typedef SecuritySummary =
{
	var threats:Int;
	var warnings:Int;
	var blockedCalls:Array<String>;
	var highRiskCallers:Array<String>;
	var authenticatedMods:Array<String>;
	var sandboxMode:Bool;
	var sessionToken:String;
}