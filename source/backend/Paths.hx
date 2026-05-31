package backend;

import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.system.System;

import lime.utils.Assets;
import flash.media.Sound;

#if MODS_ALLOWED
import backend.Mods;
#end

class Paths
{
	inline public static var SOUND_EXT:String = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT:String = "mp4";

	public static var dumpExclusions:Array<String> = ['assets/shared/music/freakyMenu.$SOUND_EXT'];
	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	public static var currentTrackedSounds:Map<String, Sound> = [];
	public static var localTrackedAssets:Array<String> = [];
	static public var currentLevel:String;

	public static function excludeAsset(key:String):Void
	{
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static function clearUnusedMemory():Void
	{
		for (key in currentTrackedAssets.keys())
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key))
			{
				var obj:FlxGraphic = currentTrackedAssets.get(key);
				if (obj != null)
				{
					@:privateAccess
					FlxG.bitmap._cache.remove(key);
					openfl.Assets.cache.removeBitmapData(key);
					currentTrackedAssets.remove(key);
					obj.persist = false;
					obj.destroyOnNoUse = true;
					obj.destroy();
				}
			}
		}

		System.gc();
		#if cpp
		cpp.NativeGc.run(true);
		#end
	}

	public static function clearStoredMemory():Void
	{
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys())
		{
			var obj:FlxGraphic = FlxG.bitmap._cache.get(key);
			if (obj != null && !currentTrackedAssets.exists(key))
			{
				openfl.Assets.cache.removeBitmapData(key);
				FlxG.bitmap._cache.remove(key);
				obj.destroy();
			}
		}

		for (key => asset in currentTrackedSounds)
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key) && asset != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}

		localTrackedAssets = [];
		#if !html5
		openfl.Assets.cache.clear("songs");
		#end
	}

	static public function setCurrentLevel(name:String):Void
	{
		currentLevel = name.toLowerCase();
	}

	public static function getPath(file:String, ?type:AssetType = TEXT, ?library:Null<String> = null, ?modsAllowed:Bool = false):String
	{
		#if MODS_ALLOWED
		if (modsAllowed)
		{
			var customFile:String = (library != null) ? '$library/$file' : file;
			var modded:String = modFolders(customFile);
			if (FileSystem.exists(modded))
				return modded;
		}
		#end

		if (library == "mobile")
			return getSharedPath('mobile/$file');

		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath:String = getLibraryPathForce(file, 'week_assets', currentLevel);
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;
		}

		return getSharedPath(file);
	}

	static public function getLibraryPath(file:String, library:String = "shared"):String
	{
		return (library == "shared") ? getSharedPath(file) : getLibraryPathForce(file, library);
	}

	inline static function getLibraryPathForce(file:String, library:String, ?level:String):String
	{
		if (level == null)
			level = library;
		return '$library:assets/$level/$file';
	}

	inline public static function getSharedPath(file:String = ''):String
	{
		return 'assets/shared/$file';
	}

	inline static public function txt(key:String, ?library:String):String
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	inline static public function xml(key:String, ?library:String):String
	{
		return getPath('data/$key.xml', TEXT, library);
	}

	inline static public function json(key:String, ?library:String):String
	{
		return getPath('data/$key.json', TEXT, library);
	}

	inline static public function shaderFragment(key:String, ?library:String):String
	{
		return getPath('shaders/$key.frag', TEXT, library);
	}

	inline static public function shaderVertex(key:String, ?library:String):String
	{
		return getPath('shaders/$key.vert', TEXT, library);
	}

	inline static public function lua(key:String, ?library:String):String
	{
		return getPath('$key.lua', TEXT, library);
	}

	static public function video(key:String):String
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if (FileSystem.exists(file))
			return file;
		#end
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	static public function sound(key:String, ?library:String):Sound
	{
		return returnSound('sounds', key, library);
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?library:String):Sound
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	inline static public function music(key:String, ?library:String):Sound
	{
		return returnSound('music', key, library);
	}

	inline static public function voices(song:String, ?postfix:String = null):Any
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if (postfix != null)
			songKey += '-$postfix';
		return returnSound(null, songKey, 'songs');
	}

	inline static public function inst(song:String):Any
	{
		return returnSound(null, '${formatToSongPath(song)}/Inst', 'songs');
	}

	static public function image(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var bitmap:BitmapData = null;
		var file:String = null;

		#if MODS_ALLOWED
		file = modsImages(key);
		if (currentTrackedAssets.exists(file))
		{
			localTrackedAssets.push(file);
			return currentTrackedAssets.get(file);
		}
		else if (FileSystem.exists(file))
			bitmap = BitmapData.fromFile(file);
		else
		#end
		{
			file = getPath('images/$key.png', IMAGE, library);
			if (currentTrackedAssets.exists(file))
			{
				localTrackedAssets.push(file);
				return currentTrackedAssets.get(file);
			}
			else if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);
		}

		if (bitmap != null)
		{
			var retVal:FlxGraphic = cacheBitmap(file, bitmap, allowGPU);
			if (retVal != null)
				return retVal;
		}

		return null;
	}

	static public function cacheBitmap(file:String, ?bitmap:BitmapData = null, ?allowGPU:Bool = true):FlxGraphic
	{
		if (bitmap == null)
		{
			#if MODS_ALLOWED
			if (FileSystem.exists(file))
				bitmap = BitmapData.fromFile(file);
			else
			#end
			if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);

			if (bitmap == null)
				return null;
		}

		localTrackedAssets.push(file);

		if (allowGPU && ClientPrefs.data.cacheOnGPU)
		{
			var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmap.width, bitmap.height, BGRA, true);
			texture.uploadFromBitmapData(bitmap);
			bitmap.image.data = null;
			bitmap.dispose();
			bitmap.disposeImage();
			bitmap = BitmapData.fromTexture(texture);
		}

		var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, file);
		newGraphic.persist = true;
		newGraphic.destroyOnNoUse = false;
		currentTrackedAssets.set(file, newGraphic);
		return newGraphic;
	}

	static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		#if sys
		#if MODS_ALLOWED
		if (!ignoreMods && FileSystem.exists(modFolders(key)))
			return File.getContent(modFolders(key));
		#end

		if (FileSystem.exists(getSharedPath(key)))
			return File.getContent(getSharedPath(key));

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath:String = getLibraryPathForce(key, 'week_assets', currentLevel);
			if (FileSystem.exists(levelPath))
				return File.getContent(levelPath);
		}
		#end

		var path:String = getPath(key, TEXT);
		if (OpenFlAssets.exists(path, TEXT))
			return Assets.getText(path);
		return null;
	}

	inline static public function font(key:String):String
	{
		#if MODS_ALLOWED
		var file:String = modsFont(key);
		if (FileSystem.exists(file))
			return file;
		#end
		return 'assets/fonts/$key';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?library:String = null):Bool
	{
		#if MODS_ALLOWED
		if (!ignoreMods)
		{
			for (mod in Mods.getGlobalMods())
				if (FileSystem.exists(mods('$mod/$key')))
					return true;

			if (FileSystem.exists(mods('${Mods.currentModDirectory}/$key')) || FileSystem.exists(mods(key)))
				return true;

			#if (android || linux || ios)
			if (FileSystem.exists(findFile('${Mods.currentModDirectory}/$key')) || FileSystem.exists(findFile(key)))
				return true;
			#end
		}
		#end

		return OpenFlAssets.exists(getPath(key, type, library, false));
	}

	static public function getAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var useMod:Bool = false;
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);

		var myXml:String = getPath('images/$key.xml', TEXT, library, true);
		if (OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end)
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(imageLoaded, useMod ? File.getContent(myXml) : myXml);
			#else
			return FlxAtlasFrames.fromSparrow(imageLoaded, myXml);
			#end
		}

		var myJson:String = getPath('images/$key.json', TEXT, library, true);
		if (OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end)
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, useMod ? File.getContent(myJson) : myJson);
			#else
			return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, myJson);
			#end
		}

		return getPackerAtlas(key, library);
	}

	inline static public function getSparrowAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var xml:String = modsXml(key);
		return FlxAtlasFrames.fromSparrow(imageLoaded, FileSystem.exists(xml) ? File.getContent(xml) : getPath('images/$key.xml', library));
		#else
		return FlxAtlasFrames.fromSparrow(imageLoaded, getPath('images/$key.xml', library));
		#end
	}

	inline static public function getPackerAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var txt:String = modsTxt(key);
		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, FileSystem.exists(txt) ? File.getContent(txt) : getPath('images/$key.txt', library));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, getPath('images/$key.txt', library));
		#end
	}

	inline static public function getAsepriteAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var json:String = modsImagesJson(key);
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, FileSystem.exists(json) ? File.getContent(json) : getPath('images/$key.json', library));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, getPath('images/$key.json', library));
		#end
	}

	inline static public function formatToSongPath(path:String):String
	{
		var invalidChars:EReg = ~/[~&\\;:<>#]/;
		var hideChars:EReg = ~/[.,'"%?!]/;
		return hideChars.split(invalidChars.split(path.replace(' ', '-')).join('-')).join('').toLowerCase();
	}

	public static function returnSound(path:Null<String>, key:String, ?library:String):Sound
	{
		#if MODS_ALLOWED
		var modLibPath:String = (library != null) ? '$library/' : '';
		if (path != null)
			modLibPath += path;

		var file:String = modsSounds(modLibPath, key);
		if (FileSystem.exists(file))
		{
			if (!currentTrackedSounds.exists(file))
				currentTrackedSounds.set(file, Sound.fromFile(file));
			localTrackedAssets.push(file);
			return currentTrackedSounds.get(file);
		}
		#end

		var gottenPath:String = (path != null) ? '$path/$key.$SOUND_EXT' : '$key.$SOUND_EXT';
		gottenPath = getPath(gottenPath, SOUND, library);
		gottenPath = gottenPath.substring(gottenPath.indexOf(':') + 1, gottenPath.length);

		if (!currentTrackedSounds.exists(gottenPath))
		{
			var retKey:String = (path != null) ? '$path/$key' : key;
			retKey = ((path == 'songs') ? 'songs:' : '') + getPath('$retKey.$SOUND_EXT', SOUND, library);
			if (OpenFlAssets.exists(retKey, SOUND))
				currentTrackedSounds.set(gottenPath, OpenFlAssets.getSound(retKey));
		}

		localTrackedAssets.push(gottenPath);
		return currentTrackedSounds.get(gottenPath);
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = ''):String
	{
		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}

	inline static public function modsFont(key:String):String     return modFolders('fonts/$key');
	inline static public function modsJson(key:String):String     return modFolders('data/$key.json');
	inline static public function modsVideo(key:String):String    return modFolders('videos/$key.$VIDEO_EXT');
	inline static public function modsSounds(path:String, key:String):String return modFolders('$path/$key.$SOUND_EXT');
	inline static public function modsImages(key:String):String   return modFolders('images/$key.png');
	inline static public function modsXml(key:String):String      return modFolders('images/$key.xml');
	inline static public function modsTxt(key:String):String      return modFolders('images/$key.txt');
	inline static public function modsImagesJson(key:String):String return modFolders('images/$key.json');

	static public function modFolders(key:String):String
	{
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods('${Mods.currentModDirectory}/$key');
			if (FileSystem.exists(fileToCheck))
				return fileToCheck;

			#if (android || linux || ios)
			var newPath:String = findFile(key);
			if (newPath != null)
				return newPath;
			#end
		}

		for (mod in Mods.getGlobalMods())
		{
			var fileToCheck:String = mods('$mod/$key');
			if (FileSystem.exists(fileToCheck))
				return fileToCheck;
		}

		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}
	#end

	#if (android || linux || ios)
	static function findFile(key:String):String
	{
		var targetParts:Array<String> = key.replace('\\', '/').split('/');
		if (targetParts.length == 0)
			return null;

		var baseDir:String = targetParts.shift();
		var searchDirs:Array<String> = [
			mods('${Mods.currentModDirectory}/$baseDir'),
			mods(baseDir)
		];

		for (part in targetParts)
		{
			if (part == '')
				continue;

			var nextDir:String = findNodeInDirs(searchDirs, part);
			if (nextDir == null)
				return null;

			searchDirs = [nextDir];
		}

		return searchDirs[0];
	}

	static function findNodeInDirs(dirs:Array<String>, key:String):String
	{
		for (dir in dirs)
		{
			var node:String = findNode(dir, key);
			if (node != null)
				return '$dir/$node';
		}
		return null;
	}

	static function findNode(dir:String, key:String):String
	{
		try
		{
			var fileMap:Map<String, String> = new Map();
			for (file in Paths.readDirectory(dir))
				fileMap.set(file.toLowerCase(), file);
			return fileMap.get(key.toLowerCase());
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}
	#end

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, ?spriteJson:Dynamic = null, ?animationJson:Dynamic = null):Void
	{
		var changedAnimJson:Bool = false;
		var changedAtlasJson:Bool = false;
		var changedImage:Bool = false;

		if (spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if (animationJson != null)
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		if (Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = (i == 0) ? '' : '$i';

				if (!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if (spriteJson != null)
					{
						changedImage = true;
						changedAtlasJson = true;
						folderOrImg = Paths.image('$originalPath/spritemap$st');
						break;
					}
				}
				else if (Paths.fileExists('images/$originalPath/spritemap$st.png', IMAGE))
				{
					changedImage = true;
					folderOrImg = Paths.image('$originalPath/spritemap$st');
					break;
				}
			}

			if (!changedImage)
			{
				changedImage = true;
				folderOrImg = Paths.image(originalPath);
			}

			if (!changedAnimJson)
			{
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}
	#end

	public static function readDirectory(directory:String):Array<String>
	{
		#if MODS_ALLOWED
		return FileSystem.readDirectory(directory);
		#else
		var dirs:Array<String> = [];
		for (dir in Assets.list().filter((folder:String) -> folder.startsWith(directory)))
		{
			@:privateAccess
			for (library in lime.utils.Assets.libraries.keys())
			{
				var libKey:String = '$library:$dir';
				if (library != 'default' && Assets.exists(libKey) && !dirs.contains(libKey) && !dirs.contains(dir))
					dirs.push(libKey);
				else if (Assets.exists(dir) && !dirs.contains(dir))
					dirs.push(dir);
			}
		}
		return dirs.map((dir:String) -> dir.substr(dir.lastIndexOf('/') + 1));
		#end
	}
}