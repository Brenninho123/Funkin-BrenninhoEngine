package api;

import haxe.Json;
import haxe.crypto.Md5;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class APISystem
{
	static final BLOCKED_FUNCTIONS:Array<String> = [
		"Sys.command",
		"Sys.exit",
		"Sys.setCwd",
		"File.saveContent",
		"File.getContent",
		"FileSystem.deleteFile",
		"FileSystem.deleteDirectory",
		"FileSystem.createDirectory",
		"Process.new",
		"cpp.Lib.command",
		"Reflect.callMethod",
		"Type.createInstance",
		"Type.resolveClass"
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
		"titleState"
	];

	static final LOG_PATH:String = "logs/api.log";

	public static var isInitialized:Bool = false;

	private static var _callLog:Array<APILogEntry> = [];
	private static var _authenticatedMods:Map<String, Bool> = new Map();
	private static var _blockedCallCount:Map<String, Int> = new Map();

	public static function init():Void
	{
		if (isInitialized)
			return;

		if (!FileSystem.exists('logs'))
			FileSystem.createDirectory('logs');

		isInitialized = true;
		log('APISystem initialized', INFO);
	}

	public static function authenticateMod(modDirectory:String):Bool
	{
		if (_authenticatedMods.exists(modDirectory))
			return _authenticatedMods.get(modDirectory);

		var packPath:String = Path.join([modDirectory, 'pack.json']);

		if (!FileSystem.exists(packPath))
		{
			log('Mod authentication failed: pack.json not found in $modDirectory', WARNING);
			_authenticatedMods.set(modDirectory, false);
			return false;
		}

		try
		{
			var content:String = File.getContent(packPath);
			var pack:Dynamic = Json.parse(content);

			if (!validateModPack(pack))
			{
				log('Mod authentication failed: invalid pack.json structure in $modDirectory', WARNING);
				_authenticatedMods.set(modDirectory, false);
				return false;
			}

			var checksum:String = Md5.encode(content);
			log('Mod authenticated: $modDirectory (checksum: $checksum)', INFO);
			_authenticatedMods.set(modDirectory, true);
			return true;
		}
		catch (e:Dynamic)
		{
			log('Mod authentication error in $modDirectory: ${e}', ERROR);
			_authenticatedMods.set(modDirectory, false);
			return false;
		}
	}

	public static function isCallBlocked(funcName:String):Bool
	{
		var blocked:Bool = BLOCKED_FUNCTIONS.contains(funcName);

		if (blocked)
		{
			var count:Int = _blockedCallCount.exists(funcName) ? _blockedCallCount.get(funcName) : 0;
			_blockedCallCount.set(funcName, count + 1);
			log('Blocked call attempt: $funcName (total attempts: ${count + 1})', WARNING);
		}

		return blocked;
	}

	public static function logCall(funcName:String, ?args:Array<Dynamic>):Void
	{
		if (!isInitialized)
			return;

		var argStr:String = (args != null && args.length > 0) ? args.map((a:Dynamic) -> Std.string(a)).join(', ') : 'none';
		log('API call: $funcName($argStr)', INFO);
	}

	public static function getBlockedCallReport():Map<String, Int>
	{
		return _blockedCallCount;
	}

	public static function clearModCache():Void
	{
		_authenticatedMods.clear();
		log('Mod authentication cache cleared', INFO);
	}

	public static function getLog():Array<APILogEntry>
	{
		return _callLog.copy();
	}

	public static function flushLog():Void
	{
		if (!isInitialized)
			return;

		var lines:Array<String> = _callLog.map((e:APILogEntry) -> '[${e.timestamp}] [${e.level}] ${e.message}');

		try
		{
			var existing:String = FileSystem.exists(LOG_PATH) ? File.getContent(LOG_PATH) : '';
			File.saveContent(LOG_PATH, existing + lines.join('\n') + '\n');
			_callLog = [];
		}
		catch (e:Dynamic) {}
	}

	private static function validateModPack(pack:Dynamic):Bool
	{
		if (pack == null)
			return false;

		if (Reflect.field(pack, 'name') == null)
			return false;

		var fields:Array<String> = Reflect.fields(pack);
		for (field in fields)
		{
			if (!ALLOWED_MOD_FIELDS.contains(field))
			{
				log('Suspicious field in pack.json: $field', WARNING);
				return false;
			}
		}

		return true;
	}

	private static function log(message:String, level:APILogLevel):Void
	{
		var entry:APILogEntry = {
			message: message,
			level: Std.string(level),
			timestamp: DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S')
		};

		_callLog.push(entry);

		if (_callLog.length >= 50)
			flushLog();
	}
}

enum APILogLevel
{
	INFO;
	WARNING;
	ERROR;
}

typedef APILogEntry =
{
	var message:String;
	var level:String;
	var timestamp:String;
}
