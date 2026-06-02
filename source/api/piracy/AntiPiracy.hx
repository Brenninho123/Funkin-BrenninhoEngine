package api.piracy;

import haxe.crypto.Sha256;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

class AntiPiracy
{
	static final GAME_TITLE:String         = "Friday Night Funkin': BrenninhoEngine";
	static final GAME_PACKAGE:String       = "com.funkin.brenninhoengine";
	static final GAME_FILE:String          = "BrenninhoEngine";
	static final AUTHOR:String             = "Brenninho";
	static final ENGINE_VERSION:String     = "0.1.1";
	static final VALID_DOMAIN:String       = "brenninhoengine";

	static final PROTECTED_FILES:Array<String> = [
		"assets/shared/images/logoBumpin.png",
		"assets/shared/images/titleEnter.png",
		"assets/shared/music/freakyMenu.ogg"
	];

	static final BLOCKED_PACKAGE_PATTERNS:Array<String> = [
		"com.shadowmario",
		"com.ninjamuffin",
		"com.kadedev",
		"net.funkin",
		"io.funkin"
	];

	static final REQUIRED_TITLE_WORDS:Array<String> = [
		"BrenninhoEngine",
		"Brenninho"
	];

	static final TAMPERED_INDICATORS:Array<String> = [
		"cracked",
		"modded",
		"patched",
		"unlocked",
		"hacked",
		"pirated",
		"nulled",
		"leaked"
	];

	static final LOG_PATH:String           = "logs/antipiracy.log";
	static final CHECKSUM_CACHE:String     = "saves/file_checksums.json";
	static final NULL_BYTE:String          = String.fromCharCode(0);

	public static var isInitialized:Bool           = false;
	public static var isVerified:Bool              = false;
	public static var onPiracyDetected:String->Void = null;
	public static var onTamperDetected:String->Void = null;
	public static var onForkDetected:String->Void   = null;

	private static var _checksumCache:Map<String, String> = new Map();
	private static var _violationLog:Array<PiracyEntry>   = [];
	private static var _violationCount:Int                = 0;
	private static var _sessionSeed:String                = '';

	public static function init():Void
	{
		if (isInitialized) return;

		if (!FileSystem.exists('logs'))
			FileSystem.createDirectory('logs');
		if (!FileSystem.exists('saves'))
			FileSystem.createDirectory('saves');

		_sessionSeed  = _generateSeed();
		isInitialized = true;

		_loadChecksumCache();
		_log('AntiPiracy initialized', INFO);
	}

	public static function verify():AntiPiracyResult
	{
		if (!isInitialized) init();

		var violations:Array<String> = [];
		var warnings:Array<String>   = [];

		_checkAppIdentity(violations, warnings);
		_checkPackageName(violations, warnings);
		_checkVersionIntegrity(violations, warnings);
		_checkFileIntegrity(violations, warnings);
		_checkEnvironment(violations, warnings);
		_checkForkIndicators(violations, warnings);
		_checkDebugBypass(violations, warnings);

		isVerified = violations.length == 0;

		var result:AntiPiracyResult = {
			verified:   isVerified,
			violations: violations,
			warnings:   warnings,
			timestamp:  DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S'),
			sessionId:  _sessionSeed.substr(0, 12)
		};

		if (!isVerified)
		{
			_violationCount += violations.length;
			_log('Verification FAILED — ${violations.length} violations', VIOLATION);
			for (v in violations) _log('VIOLATION: $v', VIOLATION);

			if (onPiracyDetected != null)
				onPiracyDetected(violations.join(' | '));

			_handleViolation(violations);
		}
		else
		{
			_log('Verification passed', INFO);
		}

		_flushLog();
		return result;
	}

	public static function registerFileChecksum(path:String):Void
	{
		if (!isInitialized) init();
		if (!FileSystem.exists(path)) return;

		try
		{
			var content:String  = File.getBytes(path).toHex();
			var checksum:String = Sha256.encode(content + _sessionSeed);
			_checksumCache.set(path, checksum);
			_saveChecksumCache();
			_log('Registered checksum: $path', INFO);
		}
		catch (e:Dynamic)
		{
			_log('Failed to register checksum: $path — $e', WARNING);
		}
	}

	public static function verifyFileChecksum(path:String):Bool
	{
		if (!isInitialized) init();
		if (!FileSystem.exists(path)) return false;
		if (!_checksumCache.exists(path)) return true;

		try
		{
			var content:String     = File.getBytes(path).toHex();
			var currentHash:String = Sha256.encode(content + _sessionSeed);
			var storedHash:String  = _checksumCache.get(path);

			if (currentHash != storedHash)
			{
				_log('Checksum mismatch: $path', VIOLATION);
				if (onTamperDetected != null) onTamperDetected(path);
				return false;
			}
			return true;
		}
		catch (e:Dynamic) { return false; }
	}

	public static function getViolationCount():Int
	{
		return _violationCount;
	}

	public static function getViolationLog(?limit:Int = 50):Array<PiracyEntry>
	{
		var copy:Array<PiracyEntry> = _violationLog.copy();
		copy.reverse();
		return copy.slice(0, limit);
	}

	public static function getReport():PiracyReport
	{
		return {
			verified:       isVerified,
			violationCount: _violationCount,
			sessionId:      _sessionSeed.substr(0, 12),
			platform:       backend.system.Main.platform,
			gameTitle:      GAME_TITLE,
			gamePackage:    GAME_PACKAGE,
			engineVersion:  ENGINE_VERSION
		};
	}

	private static function _checkAppIdentity(violations:Array<String>, warnings:Array<String>):Void
	{
		try
		{
			var appTitle:String = lime.app.Application.current.meta.get('title');
			var appFile:String  = lime.app.Application.current.meta.get('file');
			var appPkg:String   = lime.app.Application.current.meta.get('packageName');

			if (appTitle == null || appTitle.length == 0)
			{
				violations.push('App title is missing');
				return;
			}

			var titleLower:String = appTitle.toLowerCase();

			for (word in REQUIRED_TITLE_WORDS)
				if (!appTitle.contains(word))
					violations.push('Missing required title identifier: $word (found: "$appTitle")');

			for (indicator in TAMPERED_INDICATORS)
				if (titleLower.contains(indicator))
					violations.push('Tampered title indicator found: "$indicator" in "$appTitle"');

			if (appFile != null && appFile != GAME_FILE)
				warnings.push('App file name mismatch: expected "$GAME_FILE", got "$appFile"');

			if (appPkg != null && appPkg != GAME_PACKAGE)
			{
				var pkgLower:String = appPkg.toLowerCase();
				var blocked:Bool    = false;

				for (pattern in BLOCKED_PACKAGE_PATTERNS)
					if (pkgLower.contains(pattern)) { blocked = true; break; }

				if (blocked)
					violations.push('Blocked package name detected: "$appPkg"');
				else if (!pkgLower.contains(VALID_DOMAIN))
					warnings.push('Unexpected package name: "$appPkg"');
			}
		}
		catch (e:Dynamic)
		{
			warnings.push('Could not verify app identity: $e');
		}
	}

	private static function _checkPackageName(violations:Array<String>, warnings:Array<String>):Void
	{
		try
		{
			#if android
			var pkg:String = lime.app.Application.current.meta.get('packageName');
			if (pkg != null && pkg != GAME_PACKAGE)
				violations.push('Android package mismatch: expected "$GAME_PACKAGE", got "$pkg"');
			#end

			#if ios
			var bundle:String = lime.app.Application.current.meta.get('packageName');
			if (bundle != null && !bundle.contains(VALID_DOMAIN))
				warnings.push('iOS bundle ID does not contain engine domain: "$bundle"');
			#end
		}
		catch (e:Dynamic) {}
	}

	private static function _checkVersionIntegrity(violations:Array<String>, warnings:Array<String>):Void
	{
		try
		{
			var version:String = states.MainMenuState.psychEngineVersion;

			if (version == null || version.length == 0)
			{
				violations.push('Engine version is missing or empty');
				return;
			}

			if (version != ENGINE_VERSION)
				warnings.push('Engine version mismatch: expected "$ENGINE_VERSION", got "$version"');

			var versionLower:String = version.toLowerCase();
			for (indicator in TAMPERED_INDICATORS)
				if (versionLower.contains(indicator))
					violations.push('Tampered version string: "$version"');
		}
		catch (e:Dynamic)
		{
			warnings.push('Could not verify version: $e');
		}
	}

	private static function _checkFileIntegrity(violations:Array<String>, warnings:Array<String>):Void
	{
		#if sys
		for (path in PROTECTED_FILES)
		{
			if (!FileSystem.exists(path))
			{
				warnings.push('Protected file missing: $path');
				continue;
			}

			if (_checksumCache.exists(path) && !verifyFileChecksum(path))
				violations.push('Protected file tampered: $path');
		}
		#end
	}

	private static function _checkEnvironment(violations:Array<String>, warnings:Array<String>):Void
	{
		#if sys
		try
		{
			#if android
			var buildType:String = #if debug "debug" #else "release" #end;
			if (buildType == "debug")
				warnings.push('Running debug build on Android');
			#end

			#if desktop
			var cwd:String = Sys.getCwd();
			if (cwd != null)
			{
				var cwdLower:String = cwd.toLowerCase();
				for (indicator in TAMPERED_INDICATORS)
					if (cwdLower.contains(indicator))
						warnings.push('Suspicious working directory: "$cwd"');
			}
			#end
		}
		catch (e:Dynamic) {}
		#end
	}

	private static function _checkForkIndicators(violations:Array<String>, warnings:Array<String>):Void
	{
		try
		{
			var author:String = AUTHOR.toLowerCase();

			#if sys
			if (FileSystem.exists('Project.xml'))
			{
				var content:String = File.getContent('Project.xml').toLowerCase();

				if (!content.contains(author) && !content.contains(VALID_DOMAIN))
					warnings.push('Project.xml does not reference original author');

				for (indicator in TAMPERED_INDICATORS)
					if (content.contains(indicator))
						violations.push('Tampered Project.xml: "$indicator" found');
			}
			#end

			if (onForkDetected != null && warnings.length > 0)
				onForkDetected(warnings.join(' | '));
		}
		catch (e:Dynamic) {}
	}

	private static function _checkDebugBypass(violations:Array<String>, warnings:Array<String>):Void
	{
		#if debug
		warnings.push('Running in debug mode');
		#end

		#if sys
		try
		{
			var suspiciousEnvVars:Array<String> = ['CRACK', 'BYPASS', 'PATCH', 'INJECT'];
			for (v in suspiciousEnvVars)
			{
				var val:String = Sys.getEnv(v);
				if (val != null && val.length > 0)
					violations.push('Suspicious environment variable: $v=$val');
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	private static function _handleViolation(violations:Array<String>):Void
	{
		#if !debug
		if (violations.length >= 3)
		{
			_log('Critical violation threshold reached — initiating shutdown', VIOLATION);
			_flushLog();

			new FlxTimer().start(3.0, function(_:FlxTimer):Void
			{
				lime.system.System.exit(1);
			});
		}
		#end
	}

	private static function _generateSeed():String
	{
		var seed:String = Std.string(Date.now().getTime())
			+ Std.string(Math.random())
			+ GAME_PACKAGE
			+ ENGINE_VERSION
			+ backend.system.Main.platform;
		return Sha256.encode(seed);
	}

	private static function _loadChecksumCache():Void
	{
		#if sys
		if (!FileSystem.exists(CHECKSUM_CACHE)) return;
		try
		{
			var parsed:Dynamic       = Json.parse(File.getContent(CHECKSUM_CACHE));
			var fields:Array<String> = Reflect.fields(parsed);
			for (field in fields)
				_checksumCache.set(field, Reflect.field(parsed, field));
		}
		catch (e:Dynamic) { _checksumCache = new Map(); }
		#end
	}

	private static function _saveChecksumCache():Void
	{
		#if sys
		try
		{
			var obj:Dynamic = {};
			for (key => value in _checksumCache)
				Reflect.setField(obj, key, value);
			File.saveContent(CHECKSUM_CACHE, Json.stringify(obj));
		}
		catch (e:Dynamic) {}
		#end
	}

	private static function _log(message:String, level:PiracyLogLevel):Void
	{
		var entry:PiracyEntry = {
			message:   message,
			level:     Std.string(level),
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		};
		_violationLog.push(entry);
		if (_violationLog.length > 200) _violationLog.shift();
	}

	private static function _flushLog():Void
	{
		#if sys
		try
		{
			var lines:Array<String> = _violationLog.map((e:PiracyEntry) ->
				'[${e.timestamp}] [${e.level}] ${e.message}'
			);
			var existing:String = FileSystem.exists(LOG_PATH) ? File.getContent(LOG_PATH) : '';
			File.saveContent(LOG_PATH, existing + lines.join('\n') + '\n');
		}
		catch (e:Dynamic) {}
		#end
	}
}

enum PiracyLogLevel
{
	INFO;
	WARNING;
	VIOLATION;
}

typedef PiracyEntry =
{
	var message:String;
	var level:String;
	var timestamp:String;
}

typedef AntiPiracyResult =
{
	var verified:Bool;
	var violations:Array<String>;
	var warnings:Array<String>;
	var timestamp:String;
	var sessionId:String;
}

typedef PiracyReport =
{
	var verified:Bool;
	var violationCount:Int;
	var sessionId:String;
	var platform:String;
	var gameTitle:String;
	var gamePackage:String;
	var engineVersion:String;
}
