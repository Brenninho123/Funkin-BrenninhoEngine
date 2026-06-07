package backend;

import haxe.Json;

typedef ModsList =
{
	var enabled:Array<String>;
	var disabled:Array<String>;
	var all:Array<String>;
}

typedef ModPack =
{
	var name:String;
	var description:String;
	var color:String;
	var ?runsGlobally:Bool;
	var ?version:String;
	var ?author:String;
	var ?iconPath:String;
}

typedef ModEntry =
{
	var folder:String;
	var enabled:Bool;
	var pack:Null<ModPack>;
}

class Mods
{
	public static var currentModDirectory:String = '';
	public static var updatedOnState:Bool        = false;

	public static var ignoreModFolders:Array<String> = [
		'characters', 'custom_events', 'custom_notetypes', 'data',
		'songs', 'music', 'sounds', 'shaders', 'videos', 'images',
		'stages', 'weeks', 'fonts', 'scripts', 'achievements', 'states'
	];

	private static var _globalMods:Array<String>      = [];
	private static var _cachedEntries:Array<ModEntry>  = [];
	private static var _entriesDirty:Bool              = true;

	public static function getGlobalMods():Array<String>
	{
		return _globalMods;
	}

	public static function pushGlobalMods():Array<String>
	{
		_globalMods = [];
		for (mod in parseList().enabled)
		{
			var pack:Dynamic = getPack(mod);
			if (pack != null && pack.runsGlobally)
				_globalMods.push(mod);
		}
		return _globalMods;
	}

	public static function getModDirectories():Array<String>
	{
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if (!FileSystem.exists(modsFolder)) return list;

		for (folder in Paths.readDirectory(modsFolder))
		{
			var path:String = haxe.io.Path.join([modsFolder, folder]);
			if (FileSystem.isDirectory(path)
				&& !ignoreModFolders.contains(folder.toLowerCase())
				&& !list.contains(folder))
				list.push(folder);
		}
		#end
		return list;
	}

	public static function getModEntries():Array<ModEntry>
	{
		if (!_entriesDirty) return _cachedEntries.copy();

		_cachedEntries = [];
		var list:ModsList = parseList();

		for (folder in list.all)
		{
			_cachedEntries.push({
				folder:  folder,
				enabled: list.enabled.contains(folder),
				pack:    _safeParsePack(getPack(folder))
			});
		}

		_entriesDirty = false;
		return _cachedEntries.copy();
	}

	public static function invalidateCache():Void
	{
		_entriesDirty  = true;
		updatedOnState = false;
	}

	public static function mergeAllTextsNamed(path:String, defaultDirectory:String = null, allowDuplicates:Bool = false):Array<String>
	{
		if (defaultDirectory == null) defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if (!defaultDirectory.endsWith('/'))       defaultDirectory += '/';
		if (!defaultDirectory.startsWith('assets/')) defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String>      = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if (paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
			for (value in CoolUtil.coolTextFile(file))
				if ((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);

		return mergedList;
	}

	public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true):Array<String>
	{
		var folders:Array<String> = [];

		#if sys
		if (FileSystem.exists(path + fileToFind))
		#end
			folders.push(path + fileToFind);

		#if MODS_ALLOWED
		if (mods)
		{
			for (mod in Mods.getGlobalMods())
			{
				var f:String = Paths.mods('$mod/$fileToFind');
				if (FileSystem.exists(f) && !folders.contains(f)) folders.push(f);

				var fs:String = Paths.mods('$mod/states/$fileToFind');
				if (FileSystem.exists(fs) && !folders.contains(fs)) folders.push(fs);
			}

			var f:String = Paths.mods(fileToFind);
			if (FileSystem.exists(f) && !folders.contains(f)) folders.push(f);

			var fs:String = Paths.mods('states/$fileToFind');
			if (FileSystem.exists(fs) && !folders.contains(fs)) folders.push(fs);

			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var f:String = Paths.mods('${Mods.currentModDirectory}/$fileToFind');
				if (FileSystem.exists(f) && !folders.contains(f)) folders.push(f);

				var fs:String = Paths.mods('${Mods.currentModDirectory}/states/$fileToFind');
				if (FileSystem.exists(fs) && !folders.contains(fs)) folders.push(fs);
			}
		}
		#end

		return folders;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if (folder == null) folder = Mods.currentModDirectory;
		var path:String = Paths.mods('$folder/pack.json');
		if (FileSystem.exists(path))
		{
			try
			{
				#if sys
				var raw:String = File.getContent(path);
				#else
				var raw:String = Assets.getText(path);
				#end
				if (raw != null && raw.length > 0)
					return tjson.TJSON.parse(raw);
			}
			catch (e:Dynamic) {}
		}
		#end
		return null;
	}

	public static function parseList():ModsList
	{
		if (!updatedOnState) updateModList();

		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try
		{
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				if (mod.trim().length < 1) continue;
				var dat:Array<String> = mod.split('|');
				list.all.push(dat[0]);
				if (dat[1] == '1') list.enabled.push(dat[0]);
				else               list.disabled.push(dat[0]);
			}
		}
		catch (e:Dynamic) {}
		#end

		return list;
	}

	public static function setModEnabled(folder:String, enabled:Bool):Void
	{
		#if MODS_ALLOWED
		var lines:Array<String>  = CoolUtil.coolTextFile('modsList.txt');
		var result:Array<String> = [];
		var found:Bool           = false;

		for (line in lines)
		{
			if (line.trim().length < 1) continue;
			var dat:Array<String> = line.split('|');
			if (dat[0] == folder)
			{
				result.push('$folder|${enabled ? "1" : "0"}');
				found = true;
			}
			else result.push(line);
		}

		if (!found) result.push('$folder|${enabled ? "1" : "0"}');

		File.saveContent('modsList.txt', result.join('\n'));
		invalidateCache();
		#end
	}

	public static function reorderMod(folder:String, direction:Int):Void
	{
		#if MODS_ALLOWED
		var lines:Array<String> = CoolUtil.coolTextFile('modsList.txt').filter((l:String) -> l.trim().length > 0);
		var idx:Int = -1;
		for (i in 0...lines.length)
			if (lines[i].split('|')[0] == folder) { idx = i; break; }

		if (idx < 0) return;

		var newIdx:Int = Std.int(Math.max(0, Math.min(lines.length - 1, idx + direction)));
		if (newIdx == idx) return;

		var tmp:String  = lines[idx];
		lines[idx]      = lines[newIdx];
		lines[newIdx]   = tmp;

		File.saveContent('modsList.txt', lines.join('\n'));
		invalidateCache();
		#end
	}

	public static function loadTopMod():Void
	{
		currentModDirectory = '';
		#if MODS_ALLOWED
		var list:Array<String> = parseList().enabled;
		if (list != null && list.length > 0)
			currentModDirectory = list[0];
		#end
	}

	public static function isModEnabled(folder:String):Bool
	{
		return parseList().enabled.contains(folder);
	}

	public static function getModName(?folder:String = null):String
	{
		if (folder == null) folder = currentModDirectory;
		var pack:Dynamic = getPack(folder);
		if (pack != null && Reflect.field(pack, 'name') != null)
			return Std.string(Reflect.field(pack, 'name'));
		return folder;
	}

	public static function getModVersion(?folder:String = null):String
	{
		if (folder == null) folder = currentModDirectory;
		var pack:Dynamic = getPack(folder);
		if (pack != null && Reflect.field(pack, 'version') != null)
			return Std.string(Reflect.field(pack, 'version'));
		return '1.0.0';
	}

	public static function getModAuthor(?folder:String = null):String
	{
		if (folder == null) folder = currentModDirectory;
		var pack:Dynamic = getPack(folder);
		if (pack != null && Reflect.field(pack, 'author') != null)
			return Std.string(Reflect.field(pack, 'author'));
		return 'Unknown';
	}

	public static function getModColor(?folder:String = null):Int
	{
		if (folder == null) folder = currentModDirectory;
		var pack:Dynamic = getPack(folder);
		if (pack != null && Reflect.field(pack, 'color') != null)
		{
			try
			{
				var hex:String = Std.string(Reflect.field(pack, 'color')).replace('#', '');
				return Std.parseInt('0xFF$hex');
			}
			catch (e:Dynamic) {}
		}
		return 0xFFFFFFFF;
	}

	public static function getStateScript(stateKey:String):Null<String>
	{
		#if MODS_ALLOWED
		if (currentModDirectory != null && currentModDirectory.length > 0)
		{
			var hxPath:String  = Paths.mods('$currentModDirectory/states/$stateKey.hx');
			var luaPath:String = Paths.mods('$currentModDirectory/states/$stateKey.lua');

			if (FileSystem.exists(hxPath))  return hxPath;
			if (FileSystem.exists(luaPath)) return luaPath;
		}

		for (mod in _globalMods)
		{
			var hxPath:String  = Paths.mods('$mod/states/$stateKey.hx');
			var luaPath:String = Paths.mods('$mod/states/$stateKey.lua');

			if (FileSystem.exists(hxPath))  return hxPath;
			if (FileSystem.exists(luaPath)) return luaPath;
		}
		#end
		return null;
	}

	public static function hasStateScript(stateKey:String):Bool
	{
		return getStateScript(stateKey) != null;
	}

	public static function getStateScriptContent(stateKey:String):Null<String>
	{
		#if sys
		var path:String = getStateScript(stateKey);
		if (path != null && FileSystem.exists(path))
		{
			try { return File.getContent(path); }
			catch (e:Dynamic) {}
		}
		#end
		return null;
	}

	public static function listStateScripts():Array<String>
	{
		var result:Array<String> = [];
		#if MODS_ALLOWED
		var foldersToCheck:Array<String> = [];

		if (currentModDirectory != null && currentModDirectory.length > 0)
			foldersToCheck.push(Paths.mods('$currentModDirectory/states'));

		for (mod in _globalMods)
			foldersToCheck.push(Paths.mods('$mod/states'));

		for (folder in foldersToCheck)
		{
			if (!FileSystem.exists(folder)) continue;
			for (file in Paths.readDirectory(folder))
			{
				var name:String = haxe.io.Path.withoutExtension(file);
				if (!result.contains(name)
					&& (file.endsWith('.hx') || file.endsWith('.lua')))
					result.push(name);
			}
		}
		#end
		return result;
	}

	private static function updateModList():Void
	{
		#if MODS_ALLOWED
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String>        = [];

		try
		{
			for (mod in CoolUtil.coolTextFile('modsList.txt'))
			{
				var dat:Array<String> = mod.split('|');
				var folder:String     = dat[0];
				if (folder.trim().length > 0
					&& FileSystem.exists(Paths.mods(folder))
					&& FileSystem.isDirectory(Paths.mods(folder))
					&& !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, dat[1] == '1']);
				}
			}
		}
		catch (e:Dynamic) {}

		for (folder in getModDirectories())
		{
			if (folder.trim().length > 0
				&& !ignoreModFolders.contains(folder.toLowerCase())
				&& !added.contains(folder))
			{
				added.push(folder);
				list.push([folder, true]);
			}
		}

		var lines:Array<String> = list.map((v:Array<Dynamic>) -> '${v[0]}|${v[1] ? "1" : "0"}');
		File.saveContent('modsList.txt', lines.join('\n'));
		updatedOnState = true;
		invalidateCache();
		#end
	}

	private static function _safeParsePack(raw:Dynamic):Null<ModPack>
	{
		if (raw == null) return null;
		try
		{
			return {
				name:         Reflect.field(raw, 'name')         ?? 'Unknown Mod',
				description:  Reflect.field(raw, 'description')  ?? '',
				color:        Reflect.field(raw, 'color')        ?? 'FFFFFF',
				runsGlobally: Reflect.field(raw, 'runsGlobally') == true,
				version:      Reflect.field(raw, 'version')      ?? '1.0.0',
				author:       Reflect.field(raw, 'author')       ?? 'Unknown',
				iconPath:     Reflect.field(raw, 'iconPath')
			};
		}
		catch (e:Dynamic) { return null; }
	}

	#if MODS_ALLOWED
	inline public static function mods(key:String = ''):String
	{
		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}

	inline public static function modsFont(key:String):String           return modFolders('fonts/$key');
	inline public static function modsJson(key:String):String           return modFolders('data/$key.json');
	inline public static function modsVideo(key:String):String          return modFolders('videos/$key.${Paths.VIDEO_EXT}');
	inline public static function modsSounds(path:String, key:String):String return modFolders('$path/$key.${Paths.SOUND_EXT}');
	inline public static function modsImages(key:String):String         return modFolders('images/$key.png');
	inline public static function modsXml(key:String):String            return modFolders('images/$key.xml');
	inline public static function modsTxt(key:String):String            return modFolders('images/$key.txt');
	inline public static function modsImagesJson(key:String):String     return modFolders('images/$key.json');
	inline public static function modsShader(key:String):String         return modFolders('shaders/$key.frag');
	inline public static function modsLua(key:String):String            return modFolders('$key.lua');
	inline public static function modsHScript(key:String):String        return modFolders('$key.hx');
	inline public static function modsStates(key:String):String         return modFolders('states/$key');

	public static function modFolders(key:String):String
	{
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods('${Mods.currentModDirectory}/$key');
			if (FileSystem.exists(fileToCheck)) return fileToCheck;

			var statesCheck:String = mods('${Mods.currentModDirectory}/states/$key');
			if (FileSystem.exists(statesCheck)) return statesCheck;

			#if (android || linux || ios)
			var newPath:String = findFile(key);
			if (newPath != null) return newPath;
			#end
		}

		for (mod in Mods.getGlobalMods())
		{
			var fileToCheck:String = mods('$mod/$key');
			if (FileSystem.exists(fileToCheck)) return fileToCheck;

			var statesCheck:String = mods('$mod/states/$key');
			if (FileSystem.exists(statesCheck)) return statesCheck;
		}

		return #if mobile Sys.getCwd() + #end 'mods/$key';
	}
	#end

	#if (android || linux || ios)
	static function findFile(key:String):String
	{
		var parts:Array<String> = key.replace('\\', '/').split('/').filter((p:String) -> p.length > 0);
		if (parts.length == 0) return null;

		var baseDir:String           = parts.shift();
		var searchDirs:Array<String> = [
			mods('${Mods.currentModDirectory}/$baseDir'),
			mods('${Mods.currentModDirectory}/states/$baseDir'),
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
			for (file in Paths.readDirectory(dir))
				if (file.toLowerCase() == lower) return file;
		}
		catch (e:Dynamic) {}
		return null;
	}
	#end
}
