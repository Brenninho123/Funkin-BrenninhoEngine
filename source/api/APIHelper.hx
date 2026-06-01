package api;

import haxe.crypto.Md5;
import haxe.crypto.Sha256;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;

class APIHelper
{
	static final SIGNATURE_DIR:String       = "saves/signatures/";
	static final BLACKLIST_FILE:String      = "saves/blacklist.json";
	static final INTEGRITY_FILE:String      = "saves/integrity.json";
	static final MAX_CALL_RATE:Int          = 100;
	static final RATE_WINDOW_MS:Float       = 1000;
	static final MAX_SCRIPT_SIZE_KB:Int     = 512;
	static final MAX_STRING_LENGTH:Int      = 8192;
	static final SUSPICIOUS_THRESHOLD:Int   = 5;

	static final DANGEROUS_PATTERNS:Array<String> = [
		"Sys.command",
		"Sys.exit",
		"Process.new",
		"cpp.Lib.command",
		"FileSystem.deleteFile",
		"FileSystem.deleteDirectory",
		"sys.net.Socket",
		"untyped __cpp__",
		"__js__",
		"__lua__",
		"eval(",
		"loadstring(",
		"dofile(",
		"os.execute",
		"io.popen",
		"require(",
		"package.loaded"
	];

	static final TRUSTED_PATHS:Array<String> = [
		"assets/",
		"mods/",
		"saves/",
		"export/"
	];

	public static var isInitialized:Bool              = false;
	public static var onThreatDetected:String->Void   = null;
	public static var onRateLimitHit:String->Void     = null;

	private static var _callRates:Map<String, Array<Float>>  = new Map();
	private static var _blacklist:Array<String>              = [];
	private static var _integrityMap:Map<String, String>     = new Map();
	private static var _suspicionMap:Map<String, Int>        = new Map();
	private static var _auditLog:Array<AuditEntry>           = [];
	private static var _sessionKey:String                    = '';

	public static function init():Void
	{
		if (isInitialized)
			return;

		if (!FileSystem.exists(SIGNATURE_DIR))
			FileSystem.createDirectory(SIGNATURE_DIR);

		_sessionKey   = _generateSessionKey();
		isInitialized = true;

		_loadBlacklist();
		_loadIntegrityMap();
		_audit('APIHelper initialized', SYSTEM);
	}

	public static function validateCall(funcName:String, ?caller:String = 'unknown'):Bool
	{
		if (!isInitialized) init();

		if (isBlacklisted(funcName))
		{
			_recordSuspicion(caller, 'Blacklisted function call: $funcName');
			_audit('Blocked blacklisted call: $funcName from $caller', THREAT);
			return false;
		}

		if (!_checkRateLimit(funcName))
		{
			_audit('Rate limit hit: $funcName from $caller', WARNING);
			if (onRateLimitHit != null) onRateLimitHit(funcName);
			return false;
		}

		if (api.APISystem.isCallBlocked(funcName))
		{
			_recordSuspicion(caller, 'Blocked function call: $funcName');
			_audit('Blocked dangerous call: $funcName from $caller', THREAT);
			return false;
		}

		_audit('Validated call: $funcName from $caller', INFO);
		return true;
	}

	public static function scanScript(content:String, ?scriptName:String = 'unknown'):ScriptScanResult
	{
		if (!isInitialized) init();

		var threats:Array<String> = [];
		var warnings:Array<String> = [];

		if (content.length > MAX_SCRIPT_SIZE_KB * 1024)
		{
			threats.push('Script exceeds maximum size of ${MAX_SCRIPT_SIZE_KB}KB');
			_audit('Script too large: $scriptName (${content.length} bytes)', THREAT);
		}

		for (pattern in DANGEROUS_PATTERNS)
		{
			if (content.contains(pattern))
			{
				threats.push('Dangerous pattern detected: $pattern');
				_audit('Dangerous pattern "$pattern" in $scriptName', THREAT);
			}
		}

		if (_containsObfuscation(content))
			warnings.push('Script may contain obfuscated code');

		if (_containsExcessiveNesting(content))
			warnings.push('Script contains excessive nesting — possible evasion attempt');

		var result:ScriptScanResult = {
			safe:     threats.length == 0,
			threats:  threats,
			warnings: warnings,
			script:   scriptName,
			checksum: Md5.encode(content)
		};

		if (!result.safe && onThreatDetected != null)
			onThreatDetected('Script threat in $scriptName: ${threats.join(", ")}');

		return result;
	}

	public static function validatePath(path:String, ?allowExternal:Bool = false):Bool
	{
		if (!isInitialized) init();

		if (path == null || path.length == 0)
			return false;

		var normalized:String = path.replace('\\', '/').toLowerCase();

		if (normalized.contains('..'))
		{
			_audit('Path traversal attempt: $path', THREAT);
			if (onThreatDetected != null) onThreatDetected('Path traversal attempt: $path');
			return false;
		}

		if (normalized.contains('//') || normalized.contains('\0'))
		{
			_audit('Malformed path detected: $path', THREAT);
			return false;
		}

		if (!allowExternal)
		{
			var trusted:Bool = false;
			for (trustedPath in TRUSTED_PATHS)
				if (normalized.startsWith(trustedPath))
				{
					trusted = true;
					break;
				}

			if (!trusted)
			{
				_audit('Untrusted path access: $path', WARNING);
				return false;
			}
		}

		return true;
	}

	public static function validateString(input:String, ?fieldName:String = 'input'):StringValidation
	{
		if (input == null)
			return { valid: false, reason: '$fieldName is null', sanitized: '' };

		if (input.length > MAX_STRING_LENGTH)
			return { valid: false, reason: '$fieldName exceeds max length of $MAX_STRING_LENGTH', sanitized: input.substr(0, MAX_STRING_LENGTH) };

		var sanitized:String = input
			.replace('<script', '&lt;script')
			.replace('</script', '&lt;/script')
			.replace('javascript:', '')
			.replace('\0', '');

		var suspicious:Bool = false;
		for (pattern in DANGEROUS_PATTERNS)
			if (sanitized.contains(pattern))
			{
				suspicious = true;
				break;
			}

		if (suspicious)
		{
			_audit('Suspicious string in $fieldName', WARNING);
			return { valid: false, reason: 'Suspicious content in $fieldName', sanitized: sanitized };
		}

		return { valid: true, reason: '', sanitized: sanitized };
	}

	public static function signData(data:String):String
	{
		return Sha256.encode(data + _sessionKey);
	}

	public static function verifySignature(data:String, signature:String):Bool
	{
		return signData(data) == signature;
	}

	public static function registerFileIntegrity(filePath:String):Void
	{
		if (!FileSystem.exists(filePath)) return;

		try
		{
			var content:String  = File.getContent(filePath);
			var checksum:String = Sha256.encode(content);
			_integrityMap.set(filePath, checksum);
			_saveIntegrityMap();
			_audit('Registered integrity for: $filePath', INFO);
		}
		catch (e:Dynamic)
		{
			_audit('Failed to register integrity for: $filePath', WARNING);
		}
	}

	public static function verifyFileIntegrity(filePath:String):IntegrityResult
	{
		if (!_integrityMap.exists(filePath))
			return { verified: false, reason: 'No integrity record for: $filePath', path: filePath };

		if (!FileSystem.exists(filePath))
			return { verified: false, reason: 'File not found: $filePath', path: filePath };

		try
		{
			var content:String      = File.getContent(filePath);
			var currentHash:String  = Sha256.encode(content);
			var storedHash:String   = _integrityMap.get(filePath);

			if (currentHash != storedHash)
			{
				_audit('Integrity violation: $filePath', THREAT);
				if (onThreatDetected != null) onThreatDetected('File integrity violation: $filePath');
				return { verified: false, reason: 'Checksum mismatch — file may have been tampered', path: filePath };
			}

			return { verified: true, reason: '', path: filePath };
		}
		catch (e:Dynamic)
		{
			return { verified: false, reason: 'Failed to read file: $e', path: filePath };
		}
	}

	public static function blacklist(identifier:String):Void
	{
		if (!_blacklist.contains(identifier))
		{
			_blacklist.push(identifier);
			_saveBlacklist();
			_audit('Blacklisted: $identifier', SYSTEM);
		}
	}

	public static function unblacklist(identifier:String):Void
	{
		if (_blacklist.contains(identifier))
		{
			_blacklist.remove(identifier);
			_saveBlacklist();
			_audit('Removed from blacklist: $identifier', SYSTEM);
		}
	}

	public static function isBlacklisted(identifier:String):Bool
	{
		return _blacklist.contains(identifier);
	}

	public static function getSuspicionLevel(identifier:String):Int
	{
		return _suspicionMap.exists(identifier) ? _suspicionMap.get(identifier) : 0;
	}

	public static function getAuditLog(?limit:Int = 50):Array<AuditEntry>
	{
		var log:Array<AuditEntry> = _auditLog.copy();
		log.reverse();
		return limit > 0 ? log.slice(0, limit) : log;
	}

	public static function flushAuditLog():Void
	{
		try
		{
			var lines:Array<String> = _auditLog.map((e:AuditEntry) ->
				'[${e.timestamp}] [${e.level}] ${e.message}'
			);
			var logPath:String = 'logs/api_helper.log';
			if (!FileSystem.exists('logs')) FileSystem.createDirectory('logs');
			var existing:String = FileSystem.exists(logPath) ? File.getContent(logPath) : '';
			File.saveContent(logPath, existing + lines.join('\n') + '\n');
			_auditLog = [];
		}
		catch (e:Dynamic) {}
	}

	public static function getSecurityReport():SecurityReport
	{
		var threatCount:Int   = 0;
		var warningCount:Int  = 0;

		for (entry in _auditLog)
		{
			if (entry.level == 'THREAT')  threatCount++;
			if (entry.level == 'WARNING') warningCount++;
		}

		var highRiskEntities:Array<String> = [];
		for (id => score in _suspicionMap)
			if (score >= SUSPICIOUS_THRESHOLD)
				highRiskEntities.push(id);

		return {
			threats:          threatCount,
			warnings:         warningCount,
			blacklistSize:    _blacklist.length,
			highRiskEntities: highRiskEntities,
			sessionKey:       _sessionKey.substr(0, 8) + '...',
			integrityFiles:   [for (k in _integrityMap.keys()) k]
		};
	}

	private static function _checkRateLimit(funcName:String):Bool
	{
		var now:Float = Date.now().getTime();

		if (!_callRates.exists(funcName))
			_callRates.set(funcName, []);

		var calls:Array<Float> = _callRates.get(funcName);
		while (calls.length > 0 && calls[0] < now - RATE_WINDOW_MS)
			calls.shift();

		if (calls.length >= MAX_CALL_RATE)
			return false;

		calls.push(now);
		return true;
	}

	private static function _recordSuspicion(identifier:String, reason:String):Void
	{
		var current:Int = _suspicionMap.exists(identifier) ? _suspicionMap.get(identifier) : 0;
		current++;
		_suspicionMap.set(identifier, current);

		if (current >= SUSPICIOUS_THRESHOLD)
		{
			blacklist(identifier);
			_audit('Auto-blacklisted $identifier after $current suspicious actions', THREAT);
			if (onThreatDetected != null) onThreatDetected('Auto-blacklisted: $identifier');
		}
	}

	private static function _containsObfuscation(content:String):Bool
	{
		var longHexCount:Int = 0;
		var hexPattern:EReg  = ~/\\x[0-9a-fA-F]{2}/g;
		var escaped:String   = hexPattern.replace(content, '#');
		for (i in 0...escaped.length - 10)
			if (escaped.substr(i, 10).split('#').length > 5)
				longHexCount++;

		return longHexCount > 3 || content.contains('\\u00') && content.split('\\u00').length > 10;
	}

	private static function _containsExcessiveNesting(content:String):Bool
	{
		var maxDepth:Int  = 0;
		var depth:Int     = 0;
		for (i in 0...content.length)
		{
			var c:String = content.charAt(i);
			if (c == '{' || c == '(') depth++;
			else if (c == '}' || c == ')') depth--;
			if (depth > maxDepth) maxDepth = depth;
		}
		return maxDepth > 20;
	}

	private static function _generateSessionKey():String
	{
		var seed:String = Date.now().getTime()
			+ Std.string(Math.random())
			+ backend.system.Main.platform
			+ states.MainMenuState.psychEngineVersion;
		return Sha256.encode(seed);
	}

	private static function _audit(message:String, level:AuditLevel):Void
	{
		var entry:AuditEntry = {
			message:   message,
			level:     Std.string(level),
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		};
		_auditLog.push(entry);

		if (_auditLog.length >= 100)
			flushAuditLog();
	}

	private static function _loadBlacklist():Void
	{
		if (!FileSystem.exists(BLACKLIST_FILE)) return;
		try
		{
			var parsed:Dynamic = Json.parse(File.getContent(BLACKLIST_FILE));
			_blacklist = cast(parsed.blacklist, Array<String>);
		}
		catch (e:Dynamic) { _blacklist = []; }
	}

	private static function _saveBlacklist():Void
	{
		try
		{
			File.saveContent(BLACKLIST_FILE, Json.stringify({ blacklist: _blacklist }));
		}
		catch (e:Dynamic) {}
	}

	private static function _loadIntegrityMap():Void
	{
		if (!FileSystem.exists(INTEGRITY_FILE)) return;
		try
		{
			var parsed:Dynamic = Json.parse(File.getContent(INTEGRITY_FILE));
			var fields:Array<String> = Reflect.fields(parsed);
			for (field in fields)
				_integrityMap.set(field, Reflect.field(parsed, field));
		}
		catch (e:Dynamic) { _integrityMap = new Map(); }
	}

	private static function _saveIntegrityMap():Void
	{
		try
		{
			var obj:Dynamic = {};
			for (key => value in _integrityMap)
				Reflect.setField(obj, key, value);
			File.saveContent(INTEGRITY_FILE, Json.stringify(obj));
		}
		catch (e:Dynamic) {}
	}
}

enum AuditLevel
{
	INFO;
	WARNING;
	THREAT;
	SYSTEM;
}

typedef AuditEntry =
{
	var message:String;
	var level:String;
	var timestamp:String;
}

typedef ScriptScanResult =
{
	var safe:Bool;
	var threats:Array<String>;
	var warnings:Array<String>;
	var script:String;
	var checksum:String;
}

typedef StringValidation =
{
	var valid:Bool;
	var reason:String;
	var sanitized:String;
}

typedef IntegrityResult =
{
	var verified:Bool;
	var reason:String;
	var path:String;
}

typedef SecurityReport =
{
	var threats:Int;
	var warnings:Int;
	var blacklistSize:Int;
	var highRiskEntities:Array<String>;
	var sessionKey:String;
	var integrityFiles:Array<String>;
}