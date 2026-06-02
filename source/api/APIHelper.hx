package api;

import haxe.crypto.Sha256;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

class APIHelper
{
	static final SIGNATURE_DIR:String      = "saves/signatures/";
	static final BLACKLIST_FILE:String     = "saves/blacklist.json";
	static final INTEGRITY_FILE:String     = "saves/integrity.json";
	static final AUDIT_LOG_PATH:String     = "logs/api_helper.log";
	static final MAX_CALL_RATE:Int         = 100;
	static final RATE_WINDOW_MS:Float      = 1000;
	static final MAX_SCRIPT_SIZE_KB:Int    = 512;
	static final MAX_STRING_LENGTH:Int     = 8192;
	static final SUSPICIOUS_THRESHOLD:Int  = 5;
	static final MAX_AUDIT_ENTRIES:Int     = 200;
	static final NULL_BYTE:String          = String.fromCharCode(0);

	static final DANGEROUS_PATTERNS:Array<String> = [
		"Sys.command",
		"Sys.exit",
		"Sys.setCwd",
		"Sys.getEnv",
		"Sys.putEnv",
		"Process.new",
		"cpp.Lib.command",
		"cpp.Lib.load",
		"FileSystem.deleteFile",
		"FileSystem.deleteDirectory",
		"sys.net.Socket",
		"sys.net.Host",
		"sys.ssl.Socket",
		"untyped __cpp__",
		"untyped __js__",
		"__lua__",
		"eval(",
		"loadstring(",
		"dofile(",
		"loadfile(",
		"os.execute",
		"os.remove",
		"io.popen",
		"io.open",
		"require(",
		"package.loaded",
		"debug.getinfo",
		"debug.sethook",
		"haxe.macro",
		"Type.resolveClass",
		"Type.createInstance",
		"Reflect.callMethod"
	];

	static final DANGEROUS_EXTENSIONS:Array<String> = [
		".exe", ".bat", ".sh", ".cmd", ".ps1",
		".dll", ".so", ".dylib", ".bin",
		".py", ".rb", ".pl", ".php",
		".vbs", ".jar", ".class"
	];

	static final TRUSTED_PATHS:Array<String> = [
		"assets/",
		"mods/",
		"saves/",
		"export/",
		"logs/"
	];

	public static var isInitialized:Bool            = false;
	public static var onThreatDetected:String->Void = null;
	public static var onRateLimitHit:String->Void   = null;
	public static var onBlacklisted:String->Void    = null;

	private static var _callRates:Map<String, Array<Float>>  = new Map();
	private static var _blacklist:Array<String>              = [];
	private static var _integrityMap:Map<String, String>     = new Map();
	private static var _suspicionMap:Map<String, Int>        = new Map();
	private static var _auditLog:Array<AuditEntry>           = [];
	private static var _sessionKey:String                    = '';
	private static var _threatCount:Int                      = 0;
	private static var _warningCount:Int                     = 0;
	private static var _scanCount:Int                        = 0;
	private static var _blockedUntil:Map<String, Float>      = new Map();
	private static var _callHistory:Array<CallHistoryEntry>  = [];

	public static function init():Void
	{
		if (isInitialized) return;

		for (dir in [SIGNATURE_DIR, 'logs', 'saves'])
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);

		_sessionKey   = _generateSessionKey();
		isInitialized = true;

		_loadBlacklist();
		_loadIntegrityMap();
		_audit('APIHelper initialized — session ${_sessionKey.substr(0, 8)}...', SYSTEM);
	}

	public static function validateCall(funcName:String, ?caller:String = 'unknown'):Bool
	{
		if (!isInitialized) init();

		if (_isTemporarilyBlocked(caller))
		{
			_audit('Blocked caller attempted call: $funcName from $caller', THREAT);
			return false;
		}

		if (isBlacklisted(funcName))
		{
			_recordSuspicion(caller, 'Blacklisted function call: $funcName');
			_audit('Blocked blacklisted call: $funcName from $caller', THREAT);
			return false;
		}

		if (isBlacklisted(caller))
		{
			_audit('Blacklisted caller: $caller tried to call $funcName', THREAT);
			return false;
		}

		if (!_checkRateLimit(funcName))
		{
			_audit('Rate limit hit: $funcName from $caller', WARNING);
			if (onRateLimitHit != null) onRateLimitHit(funcName);
			return false;
		}

		if (api.APISystem.isCallBlocked(funcName, caller))
		{
			_recordSuspicion(caller, 'Blocked function call: $funcName');
			_audit('Blocked dangerous call: $funcName from $caller', THREAT);
			return false;
		}

		_recordCallHistory(funcName, caller, true);
		_audit('Validated call: $funcName from $caller', INFO);
		return true;
	}

	public static function scanScript(content:String, ?scriptName:String = 'unknown'):ScriptScanResult
	{
		if (!isInitialized) init();

		_scanCount++;
		var threats:Array<String>  = [];
		var warnings:Array<String> = [];

		if (content == null || content.length == 0)
			return {
				safe:     false,
				threats:  ['Empty or null script'],
				warnings: [],
				script:   scriptName,
				checksum: '',
				scanId:   _scanCount
			};

		if (content.length > MAX_SCRIPT_SIZE_KB * 1024)
		{
			threats.push('Script exceeds maximum size of ${MAX_SCRIPT_SIZE_KB}KB (${Math.round(content.length / 1024)}KB)');
			_audit('Script too large: $scriptName (${content.length} bytes)', THREAT);
		}

		for (pattern in DANGEROUS_PATTERNS)
		{
			if (content.contains(pattern))
			{
				threats.push('Dangerous pattern: $pattern');
				_audit('Dangerous pattern "$pattern" in $scriptName', THREAT);
			}
		}

		for (ext in DANGEROUS_EXTENSIONS)
			if (content.contains(ext))
				warnings.push('Reference to dangerous file type: $ext');

		if (_containsObfuscation(content))
		{
			threats.push('Obfuscated code detected');
			_audit('Obfuscation detected in $scriptName', THREAT);
		}

		if (_containsExcessiveNesting(content))
			warnings.push('Excessive nesting depth — possible evasion attempt');

		if (_containsEncodedPayload(content))
		{
			threats.push('Encoded payload detected (base64/hex)');
			_audit('Encoded payload in $scriptName', THREAT);
		}

		if (_containsInfiniteLoop(content))
			warnings.push('Possible infinite loop detected');

		var checksum:String         = Sha256.encode(content);
		var result:ScriptScanResult = {
			safe:     threats.length == 0,
			threats:  threats,
			warnings: warnings,
			script:   scriptName,
			checksum: checksum,
			scanId:   _scanCount
		};

		if (!result.safe)
		{
			_threatCount++;
			if (onThreatDetected != null)
				onThreatDetected('Script threat in $scriptName: ${threats.join(", ")}');
		}

		return result;
	}

	public static function validatePath(path:String, ?allowExternal:Bool = false):Bool
	{
		if (!isInitialized) init();

		if (path == null || path.length == 0) return false;

		var normalized:String = path.replace('\\', '/').toLowerCase();

		if (normalized.contains('..'))
		{
			_audit('Path traversal attempt: $path', THREAT);
			if (onThreatDetected != null) onThreatDetected('Path traversal: $path');
			return false;
		}

		if (normalized.contains('//') || normalized.contains(NULL_BYTE))
		{
			_audit('Malformed path: $path', THREAT);
			return false;
		}

		for (ext in DANGEROUS_EXTENSIONS)
			if (normalized.endsWith(ext))
			{
				_audit('Dangerous extension blocked: $path', THREAT);
				return false;
			}

		if (!allowExternal)
		{
			var trusted:Bool = false;
			for (trustedPath in TRUSTED_PATHS)
				if (normalized.startsWith(trustedPath)) { trusted = true; break; }

			if (!trusted)
			{
				_audit('Untrusted path access: $path', WARNING);
				_warningCount++;
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
			return {
				valid:     false,
				reason:    '$fieldName exceeds max length of $MAX_STRING_LENGTH',
				sanitized: input.substr(0, MAX_STRING_LENGTH)
			};

		var sanitized:String = input
			.replace('<script',    '&lt;script')
			.replace('</script',   '&lt;/script')
			.replace('javascript:', '')
			.replace(NULL_BYTE,    '');

		for (pattern in DANGEROUS_PATTERNS)
			if (sanitized.contains(pattern))
			{
				_audit('Suspicious string in $fieldName: $pattern', WARNING);
				_warningCount++;
				return { valid: false, reason: 'Suspicious content in $fieldName: $pattern', sanitized: sanitized };
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
		if (!isInitialized) init();
		if (!FileSystem.exists(filePath)) return;

		try
		{
			var content:String  = File.getContent(filePath);
			var checksum:String = Sha256.encode(content);
			_integrityMap.set(filePath, checksum);
			_saveIntegrityMap();
			_audit('Registered integrity: $filePath', INFO);
		}
		catch (e:Dynamic)
		{
			_audit('Failed to register integrity: $filePath — $e', WARNING);
		}
	}

	public static function verifyFileIntegrity(filePath:String):IntegrityResult
	{
		if (!isInitialized) init();

		if (!_integrityMap.exists(filePath))
			return { verified: false, reason: 'No record for: $filePath', path: filePath, tampered: false };

		if (!FileSystem.exists(filePath))
			return { verified: false, reason: 'File not found: $filePath', path: filePath, tampered: false };

		try
		{
			var content:String     = File.getContent(filePath);
			var currentHash:String = Sha256.encode(content);
			var storedHash:String  = _integrityMap.get(filePath);

			if (currentHash != storedHash)
			{
				_threatCount++;
				_audit('Integrity violation: $filePath', THREAT);
				if (onThreatDetected != null) onThreatDetected('File tampered: $filePath');
				return { verified: false, reason: 'Checksum mismatch — file may be tampered', path: filePath, tampered: true };
			}

			return { verified: true, reason: '', path: filePath, tampered: false };
		}
		catch (e:Dynamic)
		{
			return { verified: false, reason: 'Read error: $e', path: filePath, tampered: false };
		}
	}

	public static function verifyAllIntegrity():Array<IntegrityResult>
	{
		var results:Array<IntegrityResult> = [];
		for (path in _integrityMap.keys())
			results.push(verifyFileIntegrity(path));
		return results;
	}

	public static function blacklist(identifier:String, ?reason:String = ''):Void
	{
		if (!_blacklist.contains(identifier))
		{
			_blacklist.push(identifier);
			_saveBlacklist();
			_audit('Blacklisted: $identifier${reason.length > 0 ? " — $reason" : ""}', SYSTEM);
			if (onBlacklisted != null) onBlacklisted(identifier);
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

	public static function getBlacklist():Array<String>
	{
		return _blacklist.copy();
	}

	public static function getSuspicionLevel(identifier:String):Int
	{
		return _suspicionMap.exists(identifier) ? _suspicionMap.get(identifier) : 0;
	}

	public static function resetSuspicion(identifier:String):Void
	{
		_suspicionMap.remove(identifier);
		_blockedUntil.remove(identifier);
		_audit('Suspicion reset for: $identifier', SYSTEM);
	}

	public static function getAuditLog(?limit:Int = 50):Array<AuditEntry>
	{
		var log:Array<AuditEntry> = _auditLog.copy();
		log.reverse();
		return limit > 0 ? log.slice(0, limit) : log;
	}

	public static function getAuditLogByLevel(level:String, ?limit:Int = 50):Array<AuditEntry>
	{
		var filtered:Array<AuditEntry> = _auditLog.filter((e:AuditEntry) -> e.level == level);
		filtered.reverse();
		return filtered.slice(0, limit);
	}

	public static function getCallHistory(?limit:Int = 50):Array<CallHistoryEntry>
	{
		var copy:Array<CallHistoryEntry> = _callHistory.copy();
		copy.reverse();
		return copy.slice(0, limit);
	}

	public static function flushAuditLog():Void
	{
		if (_auditLog.length == 0) return;
		try
		{
			if (!FileSystem.exists('logs'))
				FileSystem.createDirectory('logs');

			var lines:Array<String> = _auditLog.map((e:AuditEntry) ->
				'[${e.timestamp}] [${e.level}] ${e.message}'
			);
			var existing:String = FileSystem.exists(AUDIT_LOG_PATH) ? File.getContent(AUDIT_LOG_PATH) : '';
			File.saveContent(AUDIT_LOG_PATH, existing + lines.join('\n') + '\n');
			_auditLog = [];
		}
		catch (e:Dynamic) {}
	}

	public static function getSecurityReport():SecurityReport
	{
		var highRiskEntities:Array<String> = [];
		for (id => score in _suspicionMap)
			if (score >= SUSPICIOUS_THRESHOLD)
				highRiskEntities.push('$id (score: $score)');

		return {
			threats:          _threatCount,
			warnings:         _warningCount,
			blacklistSize:    _blacklist.length,
			highRiskEntities: highRiskEntities,
			sessionKey:       _sessionKey.substr(0, 8) + '...',
			integrityFiles:   [for (k in _integrityMap.keys()) k],
			totalScans:       _scanCount,
			blacklist:        _blacklist.copy()
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
			blacklist(identifier, 'Auto-blacklisted after $current suspicious actions');
			_blockTemporarily(identifier);
			_threatCount++;
			_audit('Auto-blacklisted $identifier: $reason', THREAT);
			if (onThreatDetected != null) onThreatDetected('Auto-blacklisted: $identifier — $reason');
		}
		else
		{
			_warningCount++;
			_audit('Suspicion +1 for $identifier: $reason (score: $current/$SUSPICIOUS_THRESHOLD)', WARNING);
		}
	}

	private static function _blockTemporarily(identifier:String):Void
	{
		_blockedUntil.set(identifier, Date.now().getTime() + 5000);
	}

	private static function _isTemporarilyBlocked(identifier:String):Bool
	{
		if (!_blockedUntil.exists(identifier)) return false;
		if (Date.now().getTime() > _blockedUntil.get(identifier))
		{
			_blockedUntil.remove(identifier);
			return false;
		}
		return true;
	}

	private static function _recordCallHistory(funcName:String, caller:String, allowed:Bool):Void
	{
		_callHistory.push({
			func:      funcName,
			caller:    caller,
			allowed:   allowed,
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		});
		if (_callHistory.length > 500)
			_callHistory.shift();
	}

	private static function _containsObfuscation(content:String):Bool
	{
		var hexPattern:EReg = ~/\\x[0-9a-fA-F]{2}/g;
		var escaped:String  = hexPattern.replace(content, '#');
		var hexCount:Int    = escaped.split('#').length - 1;

		if (hexCount > 20) return true;
		if (content.contains('\\u00') && content.split('\\u00').length > 10) return true;

		var charCodeCount:Int = 0;
		var ccPattern:EReg    = ~/String\.fromCharCode/g;
		var temp:String       = content;
		while (ccPattern.match(temp))
		{
			charCodeCount++;
			var pos = ccPattern.matchedPos();
			temp = temp.substr(pos.pos + pos.len);
		}
		if (charCodeCount > 5) return true;

		return false;
	}

	private static function _containsExcessiveNesting(content:String):Bool
	{
		var maxDepth:Int = 0;
		var depth:Int    = 0;
		for (i in 0...content.length)
		{
			var c:String = content.charAt(i);
			if      (c == '{' || c == '(') depth++;
			else if (c == '}' || c == ')') depth--;
			if (depth > maxDepth) maxDepth = depth;
		}
		return maxDepth > 20;
	}

	private static function _containsEncodedPayload(content:String):Bool
	{
		var b64:EReg     = ~/[A-Za-z0-9+\/]{40,}={0,2}/;
		var longHex:EReg = ~/[0-9a-fA-F]{64,}/;
		return b64.match(content) || longHex.match(content);
	}

	private static function _containsInfiniteLoop(content:String):Bool
	{
		return content.contains('while(true)')
			|| content.contains('while (true)')
			|| content.contains('for(;;)')
			|| content.contains('for (;;)');
	}

	private static function _generateSessionKey():String
	{
		var seed:String = Std.string(Date.now().getTime())
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
		if (_auditLog.length >= MAX_AUDIT_ENTRIES)
			flushAuditLog();
	}

	private static function _loadBlacklist():Void
	{
		if (!FileSystem.exists(BLACKLIST_FILE)) return;
		try
		{
			var parsed:Dynamic     = Json.parse(File.getContent(BLACKLIST_FILE));
			var raw:Array<Dynamic> = cast parsed.blacklist;
			_blacklist = raw != null ? raw.map((s:Dynamic) -> Std.string(s)) : [];
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
			var parsed:Dynamic       = Json.parse(File.getContent(INTEGRITY_FILE));
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
	var scanId:Int;
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
	var tampered:Bool;
}

typedef SecurityReport =
{
	var threats:Int;
	var warnings:Int;
	var blacklistSize:Int;
	var highRiskEntities:Array<String>;
	var sessionKey:String;
	var integrityFiles:Array<String>;
	var totalScans:Int;
	var blacklist:Array<String>;
}

typedef CallHistoryEntry =
{
	var func:String;
	var caller:String;
	var allowed:Bool;
	var timestamp:String;
}