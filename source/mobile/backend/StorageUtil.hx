package mobile.backend;

import lime.system.System as LimeSystem;
import haxe.io.Path;
import haxe.Exception;

class StorageUtil
{
	#if sys
	public static final rootDir:String = LimeSystem.applicationStorageDirectory;

	public static function getStorageDirectory(?force:Bool = false):String
	{
		#if android
		var typeFile:String = rootDir + 'storagetype.txt';

		if (!FileSystem.exists(typeFile))
			File.saveContent(typeFile, ClientPrefs.data.storageType);

		var curStorageType:String = File.getContent(typeFile);
		var daPath:String         = force
			? StorageType.fromStrForce(curStorageType)
			: StorageType.fromStr(curStorageType);

		return Path.addTrailingSlash(daPath);
		#elseif ios
		return LimeSystem.documentsDirectory;
		#else
		return Sys.getCwd();
		#end
	}

	public static function saveContent(fileName:String, fileData:String, ?alert:Bool = true):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent('saves/$fileName', fileData);

			if (alert)
				CoolUtil.showPopUp('$fileName has been saved.', 'Success!');
		}
		catch (e:Exception)
		{
			if (alert)
				CoolUtil.showPopUp('$fileName couldn\'t be saved.\n(${e.message})', 'Error!');
		}
	}

	public static function fileExists(path:String):Bool
	{
		#if sys
		return FileSystem.exists(path);
		#else
		return false;
		#end
	}

	public static function ensureDirectory(path:String):Bool
	{
		try
		{
			if (!FileSystem.exists(path))
				FileSystem.createDirectory(path);
			return true;
		}
		catch (e:Dynamic) { return false; }
	}

	public static function readContent(path:String):Null<String>
	{
		try { return File.getContent(path); }
		catch (e:Dynamic) { return null; }
	}

	public static function writeContent(path:String, data:String):Bool
	{
		try { File.saveContent(path, data); return true; }
		catch (e:Dynamic) { return false; }
	}

	#if android
	public static function requestPermissions():Void
	{
		var isTiramisu:Bool = AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU;

		if (isTiramisu)
			AndroidPermissions.requestPermissions(['READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'READ_MEDIA_AUDIO']);
		else
			AndroidPermissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);

		if (!AndroidEnvironment.isExternalStorageManager())
		{
			if (AndroidVersion.SDK_INT >= AndroidVersionCode.S)
				AndroidSettings.requestSetting('REQUEST_MANAGE_MEDIA');
			AndroidSettings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
		}

		var grantedPerms:Array<String> = AndroidPermissions.getGrantedPermissions();
		var missingPerm:Bool = isTiramisu
			? !grantedPerms.contains('android.permission.READ_MEDIA_IMAGES')
			: !grantedPerms.contains('android.permission.READ_EXTERNAL_STORAGE');

		if (missingPerm)
			CoolUtil.showPopUp(
				'If you accepted the permissions you are all good!\nIf you didn\'t then expect a crash\nPress OK to see what happens',
				'Notice!'
			);

		var storageDir:String = getStorageDirectory();

		if (!ensureDirectory(storageDir))
		{
			CoolUtil.showPopUp(
				'Please create directory to\n' + getStorageDirectory(true) + '\nPress OK to close the game',
				'Error!'
			);
			LimeSystem.exit(1);
		}
	}

	public static function checkExternalPaths(?splitStorage:Bool = false):Array<String>
	{
		var process = new Process('grep -o "/storage/....-...." /proc/mounts | paste -sd \',\'');
		var paths:String = process.stdout.readAll().toString();

		if (splitStorage)
			paths = paths.replace('/storage/', '');

		var result:Array<String> = paths.split(',');
		return result.filter((p:String) -> p.length > 0);
	}

	public static function getExternalDirectory(externalDir:String):String
	{
		var daPath:String = '';

		for (path in checkExternalPaths())
			if (path.contains(externalDir))
				daPath = path;

		if (daPath.endsWith('\n'))
			daPath = daPath.substr(0, daPath.length - 1);

		return Path.addTrailingSlash(daPath);
	}

	public static function getTotalStorageGB():Float
	{
		try
		{
			var stat = new sys.io.Process('df -BG ' + getStorageDirectory());
			var output:String = stat.stdout.readAll().toString();
			var lines:Array<String> = output.split('\n');
			if (lines.length > 1)
			{
				var parts:Array<String> = lines[1].split(' ').filter((s:String) -> s.length > 0);
				if (parts.length > 1)
					return Std.parseFloat(parts[1].replace('G', ''));
			}
		}
		catch (e:Dynamic) {}
		return 0.0;
	}

	public static function getAvailableStorageGB():Float
	{
		try
		{
			var stat = new sys.io.Process('df -BG ' + getStorageDirectory());
			var output:String = stat.stdout.readAll().toString();
			var lines:Array<String> = output.split('\n');
			if (lines.length > 1)
			{
				var parts:Array<String> = lines[1].split(' ').filter((s:String) -> s.length > 0);
				if (parts.length > 3)
					return Std.parseFloat(parts[3].replace('G', ''));
			}
		}
		catch (e:Dynamic) {}
		return 0.0;
	}
	#end
	#end
}

#if android
@:runtimeValue
enum abstract StorageType(String) from String to String
{
	static final forcedPath:String      = '/storage/emulated/0/';
	static final packageNameLocal:String = 'com.funkin.brenninhoengine';
	static final fileLocal:String        = 'BrenninhoEngine';

	var EXTERNAL_DATA  = "EXTERNAL_DATA";
	var EXTERNAL_OBB   = "EXTERNAL_OBB";
	var EXTERNAL_MEDIA = "EXTERNAL_MEDIA";
	var EXTERNAL       = "EXTERNAL";

	public static function fromStr(str:String):StorageType
	{
		var pkgName:String    = lime.app.Application.current.meta.get('packageName');
		var fileName:String   = lime.app.Application.current.meta.get('file');
		var extStorage:String = AndroidEnvironment.getExternalStorageDirectory();

		return switch (str)
		{
			case "EXTERNAL_DATA":  AndroidContext.getExternalFilesDir();
			case "EXTERNAL_OBB":   AndroidContext.getObbDir();
			case "EXTERNAL_MEDIA": '$extStorage/Android/media/$pkgName';
			case "EXTERNAL":       '$extStorage/.$fileName';
			default:               StorageUtil.getExternalDirectory(str) + '.$fileLocal';
		}
	}

	public static function fromStrForce(str:String):StorageType
	{
		return switch (str)
		{
			case "EXTERNAL_DATA":  '${forcedPath}Android/data/$packageNameLocal/files';
			case "EXTERNAL_OBB":   '${forcedPath}Android/obb/$packageNameLocal';
			case "EXTERNAL_MEDIA": '${forcedPath}Android/media/$packageNameLocal';
			case "EXTERNAL":       '$forcedPath.$fileLocal';
			default:               StorageUtil.getExternalDirectory(str) + '.$fileLocal';
		}
	}

	public static function getAll():Array<StorageType>
	{
		return [EXTERNAL_DATA, EXTERNAL_OBB, EXTERNAL_MEDIA, EXTERNAL];
	}

	public static function getDisplayName(type:StorageType):String
	{
		return switch (type)
		{
			case "EXTERNAL_DATA":  'External Data';
			case "EXTERNAL_OBB":   'External OBB';
			case "EXTERNAL_MEDIA": 'External Media';
			case "EXTERNAL":       'External';
			default:               'Custom ($type)';
		}
	}
}
#end