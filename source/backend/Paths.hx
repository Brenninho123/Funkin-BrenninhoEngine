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
	inline public static var SOUND_EXT:String = #if web 'mp3' #else 'ogg' #end;
	inline public static var VIDEO_EXT:String = 'mp4';

	static final _INVALID_CHARS:EReg = ~/[~&\\;:<>#]/;
	static final _HIDE_CHARS:EReg    = ~/[.,'"%?!]/;

	public static var dumpExclusions:Array<String>             = ['assets/shared/music/freakyMenu.$SOUND_EXT'];
	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	public static var currentTrackedSounds:Map<String, Sound>      = [];
	public static var localTrackedAssets:Array<String>             = [];
	public static var currentLevel:String;

	public static function excludeAsset(key:String):Void
	{
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static function clearUnusedMemory():Void
	{
		for (key in currentTrackedAssets.keys())
		{
			if (localTrackedAssets.contains(key) || dumpExclusions.contains(key)) continue;

			var obj:FlxGraphic = currentTrackedAssets.get(key);
			if (obj == null) continue;

			@:privateAccess FlxG.bitmap._cache.remove(key);
			openfl.Assets.cache.removeBitmapData(key);
			currentTrackedAssets.remove(key);
			obj.persist        = false;
			obj.destroyOnNoUse = true;
			obj.destroy();
		}

		_runGC();
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
		openfl.Assets.cache.clear('songs');
		#end
	}

	public static function setCurrentLevel(name:String):Void
	{
		currentLevel = name.toLowerCase();
	}

	public static function getPath(file:String, ?type:AssetType = TEXT, ?library:Null<String> = null, ?modsAllowed:Bool = false):String
	{
		#if MODS_ALLOWED
		if (modsAllowed)
		{
			var customFile:String = library != null ? '$library/$file' : file;
			var modded:String     = modFolders(customFile);
			if (FileSystem.exists(modded)) return modded;
		}
		#end

		if (library == 'mobile')
			return getSharedPath('mobile/$file');

		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath:String = _libraryPathForce(file, 'week_assets', currentLevel);
			if (OpenFlAssets.exists(levelPath, type)) return levelPath;
		}

		return getSharedPath(file);
	}

	public static function getLibraryPath(file:String, library:String = 'shared'):String
	{
		return library == 'shared' ? getSharedPath(file) : _libraryPathForce(file, library);
	}

	inline static function _libraryPathForce(file:String, library:String, ?level:String):String
	{
		return '${library}:assets/${level ?? library}/$file';
	}

	inline public static function getSharedPath(file:String = ''):String
	{
		return 'assets/shared/$file';
	}

	inline public static function txt(key:String, ?library:String):String
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	inline public static function xml(key:String, ?library:String):String
	{
		return getPath('data/$key.xml', TEXT, library);
	}

	inline public static function json(key:String, ?library:String):String
	{
		return getPath('data/$key.json', TEXT, library);
	}

	inline public static function shaderFragment(key:String, ?library:String):String
	{
		return getPath('shaders/$key.frag', TEXT, library);
	}

	inline public static function shaderVertex(key:String, ?library:String):String
	{
		return getPath('shaders/$key.vert', TEXT, library);
	}

	inline public static function lua(key:String, ?library:String):String
	{
		return getPath('$key.lua', TEXT, library);
	}

	inline public static function hscript(key:String, ?library:String):String
	{
		return getPath('$key.hx', TEXT, library);
	}

	public static function video(key:String):String
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if (FileSystem.exists(file)) return file;
		#end
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	public static function sound(key:String, ?library:String):Sound
	{
		return returnSound('sounds', key, library);
	}

	inline public static function soundRandom(key:String, min:Int, max:Int, ?library:String):Sound
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	inline public static function music(key:String, ?library:String):Sound
	{
		return returnSound('music', key, library);
	}

	inline public static function voices(song:String, ?postfix:String = null):Any
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if (postfix != null) songKey += '-$postfix';
		return returnSound(null, songKey, 'songs');
	}

	inline public static function inst(song:String):Any
	{
		return returnSound(null, '${formatToSongPath(song)}/Inst', 'songs');
	}

	public static function image(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		var bitmap:BitmapData = null;
		var file:String       = null;

		#if MODS_ALLOWED
		file = modsImages(key);
		if (currentTrackedAssets.exists(file))
		{
			localTrackedAssets.push(file);
			return currentTrackedAssets.get(file);
		}
		if (FileSystem.exists(file))
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
			if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);
		}

		if (bitmap != null)
		{
			var retVal:FlxGraphic = cacheBitmap(file, bitmap, allowGPU);
			if (retVal != null) return retVal;
		}

		return null;
	}

	public static function cacheBitmap(file:String, ?bitmap:BitmapData = null, ?allowGPU:Bool = true):FlxGraphic
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

			if (bitmap == null) return null;
		}

		localTrackedAssets.push(file);

		if (allowGPU && ClientPrefs.data.cacheOnGPU)
			bitmap = _uploadToGPU(bitmap);

		var graphic:FlxGraphic      = FlxGraphic.fromBitmapData(bitmap, false, file);
		graphic.persist             = true;
		graphic.destroyOnNoUse      = false;
		currentTrackedAssets.set(file, graphic);
		return graphic;
	}

	public static function getTextFromFile(key:String, ?ignoreMods:Bool = false):Null<String>
	{
		#if sys
		#if MODS_ALLOWED
		if (!ignoreMods)
		{
			var modPath:String = modFolders(key);
			if (FileSystem.exists(modPath)) return File.getContent(modPath);
		}
		#end

		var sharedPath:String = getSharedPath(key);
		if (FileSystem.exists(sharedPath)) return File.getContent(sharedPath);

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath:String = _libraryPathForce(key, 'week_assets', currentLevel);
			if (FileSystem.exists(levelPath)) return File.getContent(levelPath);
		}
		#end

		var path:String = getPath(key, TEXT);
		if (OpenFlAssets.exists(path, TEXT)) return Assets.getText(path);
		return null;
	}

	public static function font(key:String):String
	{
		#if MODS_ALLOWED
		var file:String = modsFont(key);
		if (FileSystem.exists(file)) return file;
		#end
		return 'assets/fonts/$key';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?library:String = null):Bool
	{
		#if MODS_ALLOWED
		if (!ignoreMods)
		{
			for (mod in Mods.getGlobalMods())
				if (FileSystem.exists(mods('$mod/$key'))) return true;

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

	public static function getAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var useMod:Bool        = false;
		var graphic:FlxGraphic = image(key, library, allowGPU);

		var myXml:String = getPath('images/$key.xml', TEXT, library, true);
		if (OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end)
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(graphic, useMod ? File.getContent(myXml) : myXml);
			#else
			return FlxAtlasFrames.fromSparrow(graphic, myXml);
			#end
		}

		var myJson:String = getPath('images/$key.json', TEXT, library, true);
		if (OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end)
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromTexturePackerJson(graphic, useMod ? File.getContent(myJson) : myJson);
			#else
			return FlxAtlasFrames.fromTexturePackerJson(graphic, myJson);
			#end
		}

		return getPackerAtlas(key, library, allowGPU);
	}

	inline public static function getSparrowAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var graphic:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var xml:String = modsXml(key);
		return FlxAtlasFrames.fromSparrow(graphic, FileSystem.exists(xml) ? File.getContent(xml) : getPath('images/$key.xml', library));
		#else
		return FlxAtlasFrames.fromSparrow(graphic, getPath('images/$key.xml', library));
		#end
	}

	inline public static function getPackerAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var graphic:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var txt:String = modsTxt(key);
		return FlxAtlasFrames.fromSpriteSheetPacker(graphic, FileSystem.exists(txt) ? File.getContent(txt) : getPath('images/$key.txt', library));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(graphic, getPath('images/$key.txt', library));
		#end
	}

	inline public static function getAsepriteAtlas(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var graphic:FlxGraphic = image(key, library, allowGPU);
		#if MODS_ALLOWED
		var jsonFile:String = modsImagesJson(key);
		return FlxAtlasFrames.fromTexturePackerJson(graphic, FileSystem.exists(jsonFile) ? File.getContent(jsonFile) : getPath('images/$key.json', library));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(graphic, getPath('images/$key.json', library));
		#end
	}

	inline public static function formatToSongPath(path:String):String
	{
		return _HIDE_CHARS.split(_INVALID_CHARS.split(path.replace(' ', '-')).join('-')).join('').toLowerCase();
	}

	public static function returnSound(path:Null<String>, key:String, ?library:String):Sound
	{
		#if MODS_ALLOWED
		var modLibPath:String = library != null ? '$library/' : '';
		if (path != null) modLibPath += path;

		var file:String = modsSounds(modLibPath, key);
		if (FileSystem.exists(file))
		{
			if (!currentTrackedSounds.exists(file))
				currentTrackedSounds.set(file, Sound.fromFile(file));
			localTrackedAssets.push(file);
			return currentTrackedSounds.get(file);
		}
		#end

		var gottenPath:String = path != null ? '$path/$key.$SOUND_EXT' : '$key.$SOUND_EXT';
		gottenPath = getPath(gottenPath, SOUND, library);
		gottenPath = gottenPath.substring(gottenPath.indexOf(':') + 1);

		if (!currentTrackedSounds.exists(gottenPath))
		{
			var retKey:String = path != null ? '$path/$key' : key;
			retKey = (path == 'songs' ? 'songs:' : '') + getPath('$retKey.$SOUND_EXT', SOUND, library);
			if (OpenFlAssets.exists(retKey, SOUND))
				currentTrackedSounds.set(gottenPath, OpenFlAssets.getSound(retKey));
		}

		localTrackedAssets.push(gottenPath);
		return currentTrackedSounds.get(gottenPath);
	}

	public static function isAssetCached(key:String):Bool
	{
		return currentTrackedAssets.exists(key);
	}

	public static function isSoundCached(key:String):Bool
	{
		return currentTrackedSounds.exists(key);
	}

	public static function getCachedAssetCount():Int
	{
		return Lambda.count(currentTrackedAssets);
	}

	public static function getCachedSoundCount():Int
	{
		return Lambda.count(currentTrackedSounds);
	}

	public static function evictAsset(key:String):Bool
	{
		var graphic:FlxGraphic = currentTrackedAssets.get(key);
		if (graphic == null) return false;

		@:privateAccess FlxG.bitmap._cache.remove(key);
		openfl.Assets.cache.removeBitmapData(key);
		currentTrackedAssets.remove(key);
		localTrackedAssets.remove(key);
		graphic.persist        = false;
		graphic.destroyOnNoUse = true;
		graphic.destroy();
		return true;
	}

	public static function evictSound(key:String):Bool
	{
		if (!currentTrackedSounds.exists(key)) return false;
		Assets.cache.clear(key);
		currentTrackedSounds.remove(key);
		localTrackedAssets.remove(key);
		return true;
	}

	private static function _uploadToGPU(bitmap:BitmapData):BitmapData
	{
		var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(
			bitmap.width, bitmap.height, BGRA, true);
		texture.uploadFromBitmapData(bitmap);
		bitmap.image.data = null;
		bitmap.dispose();
		bitmap.disposeImage();
		return BitmapData.fromTexture(texture);
	}

	private static function _runGC():Void
	{
		System.gc();
		#if cpp
		cpp.NativeGc.run(true);
		#end
	}

	#if MODS_ALLOWED
	inline public static function mods(key:String = ''):String
	{
		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}

	inline public static function modsFont(key:String):String          return modFolders('fonts/$key');
	inline public static function modsJson(key:String):String          return modFolders('data/$key.json');
	inline public static function modsVideo(key:String):String         return modFolders('videos/$key.$VIDEO_EXT');
	inline public static function modsSounds(path:String, key:String):String return modFolders('$path/$key.$SOUND_EXT');
	inline public static function modsImages(key:String):String        return modFolders('images/$key.png');
	inline public static function modsXml(key:String):String           return modFolders('images/$key.xml');
	inline public static function modsTxt(key:String):String           return modFolders('images/$key.txt');
	inline public static function modsImagesJson(key:String):String    return modFolders('images/$key.json');
	inline public static function modsShader(key:String):String        return modFolders('shaders/$key.frag');
	inline public static function modsLua(key:String):String           return modFolders('$key.lua');
	inline public static function modsHScript(key:String):String       return modFolders('$key.hx');

	public static function modFolders(key:String):String
	{
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods('${Mods.currentModDirectory}/$key');
			if (FileSystem.exists(fileToCheck)) return fileToCheck;

			#if (android || linux || ios)
			var newPath:String = findFile(key);
			if (newPath != null) return newPath;
			#end
		}

		for (mod in Mods.getGlobalMods())
		{
			var fileToCheck:String = mods('$mod/$key');
			if (FileSystem.exists(fileToCheck)) return fileToCheck;
		}

		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}
	#end

	#if (android || linux || ios)
	static function findFile(key:String):String
	{
		var parts:Array<String> = key.replace('\\', '/').split('/').filter((p:String) -> p.length > 0);
		if (parts.length == 0) return null;

		var baseDir:String       = parts.shift();
		var searchDirs:Array<String> = [
			mods('${Mods.currentModDirectory}/$baseDir'),
			mods(baseDir)
		];

		for (part in parts)
		{
			var nextDir:String = _findNodeInDirs(searchDirs, part);
			if (nextDir == null) return null;
			searchDirs = [nextDir];
		}

		return searchDirs.length > 0 ? searchDirs[0] : null;
	}

	static function _findNodeInDirs(dirs:Array<String>, key:String):String
	{
		for (dir in dirs)
		{
			var node:String = _findNode(dir, key);
			if (node != null) return '$dir/$node';
		}
		return null;
	}

	static function _findNode(dir:String, key:String):String
	{
		try
		{
			var lower:String = key.toLowerCase();
			for (file in readDirectory(dir))
				if (file.toLowerCase() == lower) return file;
		}
		catch (e:Dynamic) {}
		return null;
	}
	#end

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, ?spriteJson:Dynamic = null, ?animationJson:Dynamic = null):Void
	{
		var changedAnimJson:Bool   = animationJson != null;
		var changedAtlasJson:Bool  = spriteJson    != null;
		var changedImage:Bool      = false;

		if (changedAtlasJson) spriteJson   = File.getContent(spriteJson);
		if (changedAnimJson)  animationJson = File.getContent(animationJson);

		if (Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;

			for (i in 0...10)
			{
				var suffix:String = i == 0 ? '' : '$i';

				if (!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$suffix.json');
					if (spriteJson != null)
					{
						changedImage     = true;
						changedAtlasJson = true;
						folderOrImg      = image('$originalPath/spritemap$suffix');
						break;
					}
				}
				else if (fileExists('images/$originalPath/spritemap$suffix.png', IMAGE))
				{
					changedImage = true;
					folderOrImg  = image('$originalPath/spritemap$suffix');
					break;
				}
			}

			if (!changedImage)
			{
				changedImage = true;
				folderOrImg  = image(originalPath);
			}

			if (!changedAnimJson)
			{
				changedAnimJson = true;
				animationJson   = getTextFromFile('images/$originalPath/Animation.json');
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
		var result:Array<String> = [];
		var allAssets:Array<String> = Assets.list().filter((f:String) -> f.startsWith(directory));

		for (dir in allAssets)
		{
			@:privateAccess
			for (library in lime.utils.Assets.libraries.keys())
			{
				var libKey:String = '$library:$dir';
				var useLibKey:Bool = library != 'default' && Assets.exists(libKey);
				var candidate:String = useLibKey ? libKey : dir;

				if (Assets.exists(candidate) && !result.contains(candidate) && !result.contains(dir))
					result.push(candidate);
			}
		}

		return result.map((dir:String) -> dir.substr(dir.lastIndexOf('/') + 1));
		#end
	}
}
