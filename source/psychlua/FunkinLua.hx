#if LUA_ALLOWED
package psychlua;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import openfl.utils.Assets;
import openfl.display.BitmapData;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.addons.transition.FlxTransitionableState;

#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end

import cutscenes.DialogueBoxPsych;

import objects.StrumNote;
import objects.Note;
import objects.NoteSplash;
import objects.Character;

import states.MainMenuState;
import states.StoryMenuState;
import states.FreeplayState;

import substates.PauseSubState;
import substates.GameOverSubstate;

import psychlua.LuaUtils;
import psychlua.LuaUtils.LuaTweenOptions;

#if SScript
import psychlua.HScript;
#end

import psychlua.DebugLuaText;
import psychlua.ModchartSprite;

import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import haxe.Json;

class FunkinLua
{
	public var lua:State = null;
	public var camTarget:FlxCamera;
	public var scriptName:String = '';
	public var modFolder:String = null;
	public var closed:Bool = false;

	#if HSCRIPT_ALLOWED
	public var hscript:HScript = null;
	#end

	public var callbacks:Map<String, Dynamic>             = new Map();
	public static var customFunctions:Map<String, Dynamic> = new Map();

	public var lastCalledFunction:String = '';
	public static var lastCalledScript:FunkinLua = null;

	#if (MODS_ALLOWED && !flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map();
	#end

	public function new(scriptName:String)
	{
		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		this.scriptName = scriptName.trim();

		var game:PlayState = PlayState.instance;
		game.luaArray.push(this);

		#if MODS_ALLOWED
		var myFolder:Array<String> = this.scriptName.split('/');
		if (myFolder[0] + '/' == Paths.mods()
			&& (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1])))
			this.modFolder = myFolder[1];
		#end

		_initCoreVars(game);
		_initCallbacks(game);
		_loadScript();
	}

	private function _initCoreVars(game:PlayState):Void
	{
		set('Function_StopLua',       LuaUtils.Function_StopLua);
		set('Function_StopHScript',   LuaUtils.Function_StopHScript);
		set('Function_StopAll',       LuaUtils.Function_StopAll);
		set('Function_Stop',          LuaUtils.Function_Stop);
		set('Function_Continue',      LuaUtils.Function_Continue);
		set('luaDebugMode',           false);
		set('luaDeprecatedWarnings',  true);
		set('inChartEditor',          false);

		set('curBpm',           Conductor.bpm);
		set('bpm',              PlayState.SONG.bpm);
		set('scrollSpeed',      PlayState.SONG.speed);
		set('crochet',          Conductor.crochet);
		set('stepCrochet',      Conductor.stepCrochet);
		set('songLength',       FlxG.sound.music.length);
		set('songName',         PlayState.SONG.song);
		set('songPath',         Paths.formatToSongPath(PlayState.SONG.song));
		set('startedCountdown', false);
		set('curStage',         PlayState.SONG.stage);
		set('isStoryMode',      PlayState.isStoryMode);
		set('difficulty',       PlayState.storyDifficulty);
		set('difficultyName',   Difficulty.getString());
		set('difficultyPath',   Paths.formatToSongPath(Difficulty.getString()));
		set('weekRaw',          PlayState.storyWeek);
		set('week',             WeekData.weeksList[PlayState.storyWeek]);
		set('seenCutscene',     PlayState.seenCutscene);
		set('hasVocals',        PlayState.SONG.needsVoices);

		set('cameraX',      0);
		set('cameraY',      0);
		set('screenWidth',  FlxG.width);
		set('screenHeight', FlxG.height);

		set('curSection', 0);
		set('curBeat',    0);
		set('curStep',    0);
		set('curDecBeat', 0);
		set('curDecStep', 0);

		set('score',  0);
		set('misses', 0);
		set('hits',   0);
		set('combo',  0);

		set('rating',     0);
		set('ratingName', '');
		set('ratingFC',   '');
		set('version',    MainMenuState.psychEngineVersion.trim());

		set('inGameOver',     false);
		set('mustHitSection', false);
		set('altAnim',        false);
		set('gfSection',      false);

		set('healthGainMult', game.healthGain);
		set('healthLossMult', game.healthLoss);

		#if FLX_PITCH
		set('playbackRate', game.playbackRate);
		#else
		set('playbackRate', 1);
		#end

		set('guitarHeroSustains', game.guitarHeroSustains);
		set('instakillOnMiss',    game.instakillOnMiss);
		set('botPlay',            game.cpuControlled);
		set('practice',           game.practiceMode);

		for (i in 0...4)
		{
			set('defaultPlayerStrumX$i',   0);
			set('defaultPlayerStrumY$i',   0);
			set('defaultOpponentStrumX$i', 0);
			set('defaultOpponentStrumY$i', 0);
		}

		set('defaultBoyfriendX',  game.BF_X);
		set('defaultBoyfriendY',  game.BF_Y);
		set('defaultOpponentX',   game.DAD_X);
		set('defaultOpponentY',   game.DAD_Y);
		set('defaultGirlfriendX', game.GF_X);
		set('defaultGirlfriendY', game.GF_Y);

		set('boyfriendName', PlayState.SONG.player1);
		set('dadName',       PlayState.SONG.player2);
		set('gfName',        PlayState.SONG.gfVersion);

		set('downscroll',       ClientPrefs.data.downScroll);
		set('middlescroll',     ClientPrefs.data.middleScroll);
		set('framerate',        ClientPrefs.data.framerate);
		set('ghostTapping',     ClientPrefs.data.ghostTapping);
		set('hideHud',          ClientPrefs.data.hideHud);
		set('timeBarType',      ClientPrefs.data.timeBarType);
		set('scoreZoom',        ClientPrefs.data.scoreZoom);
		set('cameraZoomOnBeat', ClientPrefs.data.camZooms);
		set('flashingLights',   ClientPrefs.data.flashing);
		set('noteOffset',       ClientPrefs.data.noteOffset);
		set('healthBarAlpha',   ClientPrefs.data.healthBarAlpha);
		set('noResetButton',    ClientPrefs.data.noReset);
		set('lowQuality',       ClientPrefs.data.lowQuality);
		set('shadersEnabled',   ClientPrefs.data.shaders);
		set('scriptName',       scriptName);
		set('currentModDirectory', Mods.currentModDirectory);

		set('noteSkin',          ClientPrefs.data.noteSkin);
		set('noteSkinPostfix',   Note.getNoteSkinPostfix());
		set('splashSkin',        ClientPrefs.data.splashSkin);
		set('splashSkinPostfix', NoteSplash.getSplashSkinPostfix());
		set('splashAlpha',       ClientPrefs.data.splashAlpha);
		set('buildTarget',       LuaUtils.getBuildTarget());
		set('platform',          backend.system.Main.platform);
	}

	private function _initCallbacks(game:PlayState):Void
	{
		for (name => func in customFunctions)
			if (func != null)
				Lua_helper.add_callback(lua, name, func);

		_registerScriptCallbacks(game);
		_registerGameplayCallbacks(game);
		_registerSpriteCallbacks(game);
		_registerTweenCallbacks(game);
		_registerSoundCallbacks(game);
		_registerCameraCallbacks(game);
		_registerInputCallbacks();
		_registerUtilCallbacks(game);
		_registerNewCallbacks(game);

		#if DISCORD_ALLOWED
		DiscordClient.addLuaCallbacks(lua);
		#end
		#if HSCRIPT_ALLOWED
		HScript.implement(this);
		#end
		#if ACHIEVEMENTS_ALLOWED
		Achievements.addLuaCallbacks(lua);
		#end
		#if flxanimate
		FlxAnimateFunctions.implement(this);
		#end

		ReflectionFunctions.implement(this);
		TextFunctions.implement(this);
		ExtraFunctions.implement(this);
		CustomSubstate.implement(this);
		ShaderFunctions.implement(this);
		DeprecatedFunctions.implement(this);

		#if mobile
  mobile.psychlua.MobileFunctions.implement(this);
  #if android
  mobile.psychlua.AndroidFunctions.implement(this);
  #end
  #end
	}

	private function _registerScriptCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "getRunningScripts", function():Array<String>
		{
			return game.luaArray.map((s:FunkinLua) -> s.scriptName);
		});

		addLocalCallback("setOnScripts", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null):Void
		{
			if (exclusions == null) exclusions = [];
			if (ignoreSelf && !exclusions.contains(scriptName)) exclusions.push(scriptName);
			game.setOnScripts(varName, arg, exclusions);
		});

		addLocalCallback("setOnHScript", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null):Void
		{
			if (exclusions == null) exclusions = [];
			if (ignoreSelf && !exclusions.contains(scriptName)) exclusions.push(scriptName);
			game.setOnHScript(varName, arg, exclusions);
		});

		addLocalCallback("setOnLuas", function(varName:String, arg:Dynamic, ?ignoreSelf:Bool = false, ?exclusions:Array<String> = null):Void
		{
			if (exclusions == null) exclusions = [];
			if (ignoreSelf && !exclusions.contains(scriptName)) exclusions.push(scriptName);
			game.setOnLuas(varName, arg, exclusions);
		});

		addLocalCallback("callOnScripts", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Bool
		{
			if (excludeScripts == null) excludeScripts = [];
			if (ignoreSelf && !excludeScripts.contains(scriptName)) excludeScripts.push(scriptName);
			game.callOnScripts(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		addLocalCallback("callOnLuas", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Bool
		{
			if (excludeScripts == null) excludeScripts = [];
			if (ignoreSelf && !excludeScripts.contains(scriptName)) excludeScripts.push(scriptName);
			game.callOnLuas(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		addLocalCallback("callOnHScript", function(funcName:String, ?args:Array<Dynamic> = null, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true, ?excludeScripts:Array<String> = null, ?excludeValues:Array<Dynamic> = null):Bool
		{
			if (excludeScripts == null) excludeScripts = [];
			if (ignoreSelf && !excludeScripts.contains(scriptName)) excludeScripts.push(scriptName);
			game.callOnHScript(funcName, args, ignoreStops, excludeScripts, excludeValues);
			return true;
		});

		Lua_helper.add_callback(lua, "callScript", function(luaFile:String, funcName:String, ?args:Array<Dynamic> = null):Void
		{
			if (args == null) args = [];
			var foundScript:String = findScript(luaFile);
			if (foundScript == null) return;
			for (inst in game.luaArray)
				if (inst.scriptName == foundScript)
				{
					inst.call(funcName, args);
					return;
				}
		});

		Lua_helper.add_callback(lua, "isRunning", function(luaFile:String):Bool
		{
			var foundScript:String = findScript(luaFile);
			if (foundScript == null) return false;
			for (inst in game.luaArray)
				if (inst.scriptName == foundScript)
					return true;
			return false;
		});

		Lua_helper.add_callback(lua, "addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false):Void
		{
			var foundScript:String = findScript(luaFile);
			if (foundScript == null)
			{
				luaTrace("addLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
				return;
			}
			if (!ignoreAlreadyRunning)
				for (inst in game.luaArray)
					if (inst.scriptName == foundScript)
					{
						luaTrace('addLuaScript: Script "$foundScript" is already running!');
						return;
					}
			new FunkinLua(foundScript);
		});

		Lua_helper.add_callback(lua, "addHScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false):Void
		{
			#if HSCRIPT_ALLOWED
			var foundScript:String = findScript(luaFile, '.hx');
			if (foundScript == null)
			{
				luaTrace("addHScript: Script doesn't exist!", false, false, FlxColor.RED);
				return;
			}
			if (!ignoreAlreadyRunning)
				for (script in game.hscriptArray)
					if (script.origin == foundScript)
					{
						luaTrace('addHScript: Script "$foundScript" is already running!');
						return;
					}
			PlayState.instance.initHScript(foundScript);
			#else
			luaTrace("addHScript: HScript is not supported on this platform!", false, false, FlxColor.RED);
			#end
		});

		Lua_helper.add_callback(lua, "removeLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false):Bool
		{
			var foundScript:String = findScript(luaFile);
			if (foundScript != null)
				for (inst in game.luaArray)
					if (inst.scriptName == foundScript)
					{
						inst.stop();
						return true;
					}
			luaTrace('removeLuaScript: Script $luaFile isn\'t running!', false, false, FlxColor.RED);
			return false;
		});

		Lua_helper.add_callback(lua, "removeHScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false):Bool
		{
			#if HSCRIPT_ALLOWED
			var foundScript:String = findScript(luaFile, '.hx');
			if (foundScript != null)
				for (script in game.hscriptArray)
					if (script.origin == foundScript)
					{
						script.destroy();
						return true;
					}
			luaTrace('removeHScript: Script $luaFile isn\'t running!', false, false, FlxColor.RED);
			return false;
			#else
			luaTrace("removeHScript: HScript is not supported on this platform!", false, false, FlxColor.RED);
			return false;
			#end
		});

		Lua_helper.add_callback(lua, "getGlobalFromScript", function(luaFile:String, global:String):Void
		{
			var foundScript:String = findScript(luaFile);
			if (foundScript == null) return;
			for (inst in game.luaArray)
			{
				if (inst.scriptName != foundScript) continue;
				Lua.getglobal(inst.lua, global);
				if      (Lua.isnumber(inst.lua,  -1)) Lua.pushnumber(lua,  Lua.tonumber(inst.lua,  -1));
				else if (Lua.isstring(inst.lua,  -1)) Lua.pushstring(lua,  Lua.tostring(inst.lua,  -1));
				else if (Lua.isboolean(inst.lua, -1)) Lua.pushboolean(lua, Lua.toboolean(inst.lua, -1));
				else                                   Lua.pushnil(lua);
				Lua.pop(inst.lua, 1);
				return;
			}
		});

		Lua_helper.add_callback(lua, "setGlobalFromScript", function(luaFile:String, global:String, val:Dynamic):Void
		{
			var foundScript:String = findScript(luaFile);
			if (foundScript == null) return;
			for (inst in game.luaArray)
				if (inst.scriptName == foundScript)
					inst.set(global, val);
		});

		Lua_helper.add_callback(lua, "setVar", function(varName:String, value:Dynamic):Dynamic
		{
			PlayState.instance.variables.set(varName, value);
			return value;
		});

		Lua_helper.add_callback(lua, "getVar", function(varName:String):Dynamic
		{
			return PlayState.instance.variables.get(varName);
		});

		addLocalCallback("close", function():Bool
		{
			closed = true;
			return closed;
		});

		Lua_helper.add_callback(lua, "debugPrint", function(text:Dynamic = '', color:String = 'WHITE'):Void
		{
			PlayState.instance.addTextToDebug(text, CoolUtil.colorFromString(color));
		});
	}

	private function _registerGameplayCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "loadSong", function(?name:String = null, ?difficultyNum:Int = -1):Void
		{
			if (name == null || name.length < 1) name = PlayState.SONG.song;
			if (difficultyNum == -1) difficultyNum = PlayState.storyDifficulty;
			PlayState.SONG = Song.loadFromJson(Highscore.formatSong(name, difficultyNum), name);
			PlayState.storyDifficulty = difficultyNum;
			game.persistentUpdate = false;
			LoadingState.loadAndSwitchState(new PlayState());
			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
			if (game.vocals != null)
			{
				game.vocals.pause();
				game.vocals.volume = 0;
			}
			FlxG.camera.followLerp = 0;
		});

		Lua_helper.add_callback(lua, "startCountdown",  function():Bool { game.startCountdown(); return true; });
		Lua_helper.add_callback(lua, "endSong",         function():Bool { game.KillNotes(); game.endSong(); return true; });
		Lua_helper.add_callback(lua, "getSongPosition", function():Float return Conductor.songPosition);

		Lua_helper.add_callback(lua, "restartSong", function(?skipTransition:Bool = false):Bool
		{
			game.persistentUpdate = false;
			FlxG.camera.followLerp = 0;
			PauseSubState.restartSong(skipTransition);
			return true;
		});

		Lua_helper.add_callback(lua, "exitSong", function(?skipTransition:Bool = false):Bool
		{
			if (skipTransition)
			{
				FlxTransitionableState.skipNextTransIn  = true;
				FlxTransitionableState.skipNextTransOut = true;
			}
			MusicBeatState.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
			#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			PlayState.changedDifficulty = false;
			PlayState.chartingMode      = false;
			game.transitioning          = true;
			FlxG.camera.followLerp      = 0;
			Mods.loadTopMod();
			return true;
		});

		Lua_helper.add_callback(lua, "addScore",  function(v:Int = 0):Void { game.songScore  += v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "addMisses", function(v:Int = 0):Void { game.songMisses += v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "addHits",   function(v:Int = 0):Void { game.songHits   += v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "setScore",  function(v:Int = 0):Void { game.songScore   = v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "setMisses", function(v:Int = 0):Void { game.songMisses  = v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "setHits",   function(v:Int = 0):Void { game.songHits    = v; game.RecalculateRating(); });
		Lua_helper.add_callback(lua, "getScore",  function():Int   return game.songScore);
		Lua_helper.add_callback(lua, "getMisses", function():Int   return game.songMisses);
		Lua_helper.add_callback(lua, "getHits",   function():Int   return game.songHits);
		Lua_helper.add_callback(lua, "getCombo",  function():Int   return game.combo);
		Lua_helper.add_callback(lua, "resetCombo", function():Void { game.combo = 0; });

		Lua_helper.add_callback(lua, "setHealth", function(v:Float = 0):Void { game.health  = v; });
		Lua_helper.add_callback(lua, "addHealth", function(v:Float = 0):Void { game.health += v; });
		Lua_helper.add_callback(lua, "getHealth", function():Float return game.health);

		Lua_helper.add_callback(lua, "setRatingPercent", function(v:Float):Void  { game.ratingPercent = v; });
		Lua_helper.add_callback(lua, "setRatingName",    function(v:String):Void { game.ratingName = v; });
		Lua_helper.add_callback(lua, "setRatingFC",      function(v:String):Void { game.ratingFC = v; });

		Lua_helper.add_callback(lua, "triggerEvent", function(name:String, arg1:Dynamic, arg2:Dynamic):Bool
		{
			game.triggerEvent(name, Std.string(arg1), Std.string(arg2), Conductor.songPosition);
			return true;
		});

		Lua_helper.add_callback(lua, "characterDance", function(character:String):Void
		{
			switch (character.toLowerCase())
			{
				case 'dad':               game.dad.dance();
				case 'gf' | 'girlfriend': if (game.gf != null) game.gf.dance();
				default:                  game.boyfriend.dance();
			}
		});

		Lua_helper.add_callback(lua, "getCharacterX", function(type:String):Float
		{
			return switch (type.toLowerCase()) {
				case 'dad' | 'opponent': game.dadGroup.x;
				case 'gf' | 'girlfriend': game.gfGroup.x;
				default: game.boyfriendGroup.x;
			};
		});

		Lua_helper.add_callback(lua, "setCharacterX", function(type:String, value:Float):Void
		{
			switch (type.toLowerCase()) {
				case 'dad' | 'opponent':  game.dadGroup.x = value;
				case 'gf' | 'girlfriend': game.gfGroup.x  = value;
				default:                   game.boyfriendGroup.x = value;
			}
		});

		Lua_helper.add_callback(lua, "getCharacterY", function(type:String):Float
		{
			return switch (type.toLowerCase()) {
				case 'dad' | 'opponent': game.dadGroup.y;
				case 'gf' | 'girlfriend': game.gfGroup.y;
				default: game.boyfriendGroup.y;
			};
		});

		Lua_helper.add_callback(lua, "setCharacterY", function(type:String, value:Float):Void
		{
			switch (type.toLowerCase()) {
				case 'dad' | 'opponent':  game.dadGroup.y = value;
				case 'gf' | 'girlfriend': game.gfGroup.y  = value;
				default:                   game.boyfriendGroup.y = value;
			}
		});

		Lua_helper.add_callback(lua, "getCharacterAlpha", function(type:String):Float
		{
			return switch (type.toLowerCase()) {
				case 'dad' | 'opponent': game.dadGroup.alpha;
				case 'gf' | 'girlfriend': game.gfGroup.alpha;
				default: game.boyfriendGroup.alpha;
			};
		});

		Lua_helper.add_callback(lua, "setCharacterAlpha", function(type:String, value:Float):Void
		{
			switch (type.toLowerCase()) {
				case 'dad' | 'opponent':  game.dadGroup.alpha = value;
				case 'gf' | 'girlfriend': game.gfGroup.alpha  = value;
				default:                   game.boyfriendGroup.alpha = value;
			}
		});

		Lua_helper.add_callback(lua, "getCharacterVisible", function(type:String):Bool
		{
			return switch (type.toLowerCase()) {
				case 'dad' | 'opponent': game.dadGroup.visible;
				case 'gf' | 'girlfriend': game.gfGroup.visible;
				default: game.boyfriendGroup.visible;
			};
		});

		Lua_helper.add_callback(lua, "setCharacterVisible", function(type:String, value:Bool):Void
		{
			switch (type.toLowerCase()) {
				case 'dad' | 'opponent':  game.dadGroup.visible = value;
				case 'gf' | 'girlfriend': game.gfGroup.visible  = value;
				default:                   game.boyfriendGroup.visible = value;
			}
		});

		Lua_helper.add_callback(lua, "addCharacterToList", function(name:String, type:String):Void
		{
			var charType:Int = switch (type.toLowerCase()) {
				case 'dad': 1;
				case 'gf' | 'girlfriend': 2;
				default: 0;
			};
			game.addCharacterToList(name, charType);
		});

		Lua_helper.add_callback(lua, "getNoteCount",  function():Int   return game.notes.length);
		Lua_helper.add_callback(lua, "getBPM",        function():Float return Conductor.bpm);
		Lua_helper.add_callback(lua, "getSongSpeed",  function():Float return PlayState.SONG.speed);
		Lua_helper.add_callback(lua, "setSongSpeed",  function(v:Float):Void { PlayState.SONG.speed = v; });
		Lua_helper.add_callback(lua, "getStage",      function():String return PlayState.SONG.stage);
		Lua_helper.add_callback(lua, "getWeekName",   function():String return WeekData.weeksList[PlayState.storyWeek]);

		Lua_helper.add_callback(lua, "isPlayerNote", function(noteIndex:Int):Bool
		{
			if (noteIndex < 0 || noteIndex >= game.notes.length) return false;
			return game.notes.members[noteIndex].mustPress;
		});

		Lua_helper.add_callback(lua, "setNoteAlpha", function(noteIndex:Int, value:Float):Void
		{
			if (noteIndex >= 0 && noteIndex < game.notes.length)
				game.notes.members[noteIndex].alpha = value;
		});

		Lua_helper.add_callback(lua, "setStrumAlpha", function(index:Int, value:Float):Void
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				game.strumLineNotes.members[index].alpha = value;
		});

		Lua_helper.add_callback(lua, "setStrumVisible", function(index:Int, value:Bool):Void
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				game.strumLineNotes.members[index].visible = value;
		});

		Lua_helper.add_callback(lua, "setStrumX", function(index:Int, value:Float):Void
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				game.strumLineNotes.members[index].x = value;
		});

		Lua_helper.add_callback(lua, "setStrumY", function(index:Int, value:Float):Void
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				game.strumLineNotes.members[index].y = value;
		});

		Lua_helper.add_callback(lua, "getStrumX", function(index:Int):Float
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				return game.strumLineNotes.members[index].x;
			return 0;
		});

		Lua_helper.add_callback(lua, "getStrumY", function(index:Int):Float
		{
			if (index >= 0 && index < game.strumLineNotes.length)
				return game.strumLineNotes.members[index].y;
			return 0;
		});

		Lua_helper.add_callback(lua, "forceEndSong", function():Void
		{
			game.KillNotes();
			game.endSong();
		});

		Lua_helper.add_callback(lua, "setGameOverChar", function(charName:String):Void
		{
			GameOverSubstate.characterName = charName;
		});

		Lua_helper.add_callback(lua, "setHudVisible", function(value:Bool):Void
		{
			game.camHUD.visible = value;
		});

		Lua_helper.add_callback(lua, "setGameVisible", function(value:Bool):Void
		{
			game.camGame.visible = value;
		});

		Lua_helper.add_callback(lua, "setLowQuality", function(value:Bool):Void
		{
			ClientPrefs.data.lowQuality = value;
		});

		Lua_helper.add_callback(lua, "setAntialiasing", function(value:Bool):Void
		{
			ClientPrefs.data.antialiasing = value;
		});

		Lua_helper.add_callback(lua, "precacheImage", function(name:String, ?allowGPU:Bool = true):Void { Paths.image(name, allowGPU); });
		Lua_helper.add_callback(lua, "precacheSound", function(name:String):Void { Paths.sound(name); });
		Lua_helper.add_callback(lua, "precacheMusic", function(name:String):Void { Paths.music(name); });

		Lua_helper.add_callback(lua, "startDialogue", function(dialogueFile:String, music:String = null):Bool
		{
			var songPath:String = Paths.formatToSongPath(PlayState.SONG.song);
			var path:String;
			#if MODS_ALLOWED
			path = Paths.modsJson('$songPath/$dialogueFile');
			if (!FileSystem.exists(path))
			#end
				path = Paths.json('$songPath/$dialogueFile');

			#if MODS_ALLOWED
			var exists:Bool = FileSystem.exists(path);
			#else
			var exists:Bool = Assets.exists(path);
			#end

			if (!exists)
			{
				luaTrace('startDialogue: Dialogue file not found', false, false, FlxColor.RED);
				if (game.endingSong) game.endSong(); else game.startCountdown();
				return false;
			}

			var shit:DialogueFile = DialogueBoxPsych.parseDialogue(path);
			if (shit.dialogue.length > 0)
			{
				game.startDialogue(shit, music);
				return true;
			}
			luaTrace('startDialogue: Dialogue file is badly formatted!', false, false, FlxColor.RED);
			return false;
		});

		Lua_helper.add_callback(lua, "startVideo", function(videoFile:String):Bool
		{
			#if VIDEOS_ALLOWED
			if (FileSystem.exists(Paths.video(videoFile)))
			{
				game.startVideo(videoFile);
				return true;
			}
			luaTrace('startVideo: Video file not found: $videoFile', false, false, FlxColor.RED);
			return false;
			#else
			if (game.endingSong) game.endSong(); else game.startCountdown();
			return true;
			#end
		});

		#if MODS_ALLOWED
		addLocalCallback("getModSetting", function(saveTag:String, ?modName:String = null):Dynamic
		{
			if (modName == null)
			{
				if (this.modFolder == null)
				{
					luaTrace('getModSetting: Argument #2 is null and script is not inside a packed Mod folder!', false, false, FlxColor.RED);
					return null;
				}
				modName = this.modFolder;
			}
			return LuaUtils.getModSetting(saveTag, modName);
		});
		#end
	}

	private function _registerSpriteCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "makeLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0):Void
		{
			tag = tag.replace('.', '');
			LuaUtils.resetSpriteTag(tag);
			var spr:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
				spr.loadGraphic(Paths.image(image));
			spr.active = true;
			game.modchartSprites.set(tag, spr);
		});

		Lua_helper.add_callback(lua, "makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = "sparrow"):Void
		{
			tag = tag.replace('.', '');
			LuaUtils.resetSpriteTag(tag);
			var spr:ModchartSprite = new ModchartSprite(x, y);
			LuaUtils.loadFrames(spr, image, spriteType);
			game.modchartSprites.set(tag, spr);
		});

		Lua_helper.add_callback(lua, "makeGraphic", function(obj:String, width:Int = 256, height:Int = 256, color:String = 'FFFFFF'):Void
		{
			var spr:FlxSprite = LuaUtils.getObjectDirectly(obj, false);
			if (spr != null) spr.makeGraphic(width, height, CoolUtil.colorFromString(color));
		});

		Lua_helper.add_callback(lua, "addLuaSprite", function(tag:String, front:Bool = false):Bool
		{
			var spr:FlxSprite = game.modchartSprites.exists(tag) ? game.modchartSprites.get(tag)
				: game.variables.exists(tag) ? game.variables.get(tag) : null;
			if (spr == null) return false;
			if (front)
				LuaUtils.getTargetInstance().add(spr);
			else if (!game.isDead)
				game.insert(game.members.indexOf(LuaUtils.getLowestCharacterGroup()), spr);
			else
				GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), spr);
			return true;
		});

		Lua_helper.add_callback(lua, "removeLuaSprite", function(tag:String, destroy:Bool = true):Void
		{
			if (!game.modchartSprites.exists(tag)) return;
			var spr:ModchartSprite = game.modchartSprites.get(tag);
			if (destroy) spr.kill();
			LuaUtils.getTargetInstance().remove(spr, true);
			if (destroy) { spr.destroy(); game.modchartSprites.remove(tag); }
		});

		Lua_helper.add_callback(lua, "loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0):Void
		{
			var spr:FlxSprite = _getSpriteFromVar(variable);
			if (spr != null && image != null && image.length > 0)
				spr.loadGraphic(Paths.image(image), gridX != 0 || gridY != 0, gridX, gridY);
		});

		Lua_helper.add_callback(lua, "loadFrames", function(variable:String, image:String, spriteType:String = "sparrow"):Void
		{
			var spr:FlxSprite = _getSpriteFromVar(variable);
			if (spr != null && image != null && image.length > 0)
				LuaUtils.loadFrames(spr, image, spriteType);
		});

		Lua_helper.add_callback(lua, "setGraphicSize", function(obj:String, x:Int, y:Int = 0, updateHitbox:Bool = true):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) { spr.setGraphicSize(x, y); if (updateHitbox) spr.updateHitbox(); return; }
			luaTrace('setGraphicSize: Couldn\'t find object: $obj', false, false, FlxColor.RED);
		});

		Lua_helper.add_callback(lua, "scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) { spr.scale.set(x, y); if (updateHitbox) spr.updateHitbox(); return; }
			luaTrace('scaleObject: Couldn\'t find object: $obj', false, false, FlxColor.RED);
		});

		Lua_helper.add_callback(lua, "updateHitbox", function(obj:String):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : cast Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if (spr != null) { spr.updateHitbox(); return; }
			luaTrace('updateHitbox: Couldn\'t find object: $obj', false, false, FlxColor.RED);
		});

		Lua_helper.add_callback(lua, "updateHitboxFromGroup", function(group:String, index:Int):Void
		{
			var g:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), group);
			if (Std.isOfType(g, FlxTypedGroup)) (cast g:FlxTypedGroup<Dynamic>).members[index].updateHitbox();
			else g[index].updateHitbox();
		});

		Lua_helper.add_callback(lua, "addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true):Bool
		{
			var o:Dynamic = LuaUtils.getObjectDirectly(obj, false);
			if (o != null && o.animation != null)
			{
				o.animation.addByPrefix(name, prefix, framerate, loop);
				if (o.animation.curAnim == null)
				{
					if (o.playAnim != null) o.playAnim(name, true);
					else o.animation.play(name, true);
				}
				return true;
			}
			return false;
		});

		Lua_helper.add_callback(lua, "addAnimation", function(obj:String, name:String, frames:Array<Int>, framerate:Int = 24, loop:Bool = true):Bool
		{
			var o:Dynamic = LuaUtils.getObjectDirectly(obj, false);
			if (o != null && o.animation != null)
			{
				o.animation.add(name, frames, framerate, loop);
				if (o.animation.curAnim == null) o.animation.play(name, true);
				return true;
			}
			return false;
		});

		Lua_helper.add_callback(lua, "addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Int = 24, loop:Bool = false):Bool
		{
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
		});

		Lua_helper.add_callback(lua, "playAnim", function(obj:String, name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0):Bool
		{
			var o:Dynamic = LuaUtils.getObjectDirectly(obj, false);
			if (o == null) return false;
			if (o.playAnim != null) o.playAnim(name, forced, reverse, startFrame);
			else if (o.anim != null) o.anim.play(name, forced, reverse, startFrame);
			else o.animation.play(name, forced, reverse, startFrame);
			return true;
		});

		Lua_helper.add_callback(lua, "addOffset", function(obj:String, anim:String, x:Float, y:Float):Bool
		{
			var o:Dynamic = LuaUtils.getObjectDirectly(obj, false);
			if (o != null && o.addOffset != null) { o.addOffset(anim, x, y); return true; }
			return false;
		});

		Lua_helper.add_callback(lua, "setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float):Void
		{
			var luaObj:FlxSprite = game.getLuaObject(obj, false);
			if (luaObj != null) { luaObj.scrollFactor.set(scrollX, scrollY); return; }
			var object:FlxObject = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if (object != null) object.scrollFactor.set(scrollX, scrollY);
		});

		Lua_helper.add_callback(lua, "screenCenter", function(obj:String, pos:String = 'xy'):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr == null) { luaTrace('screenCenter: Object $obj doesn\'t exist!', false, false, FlxColor.RED); return; }
			switch (pos.trim().toLowerCase()) {
				case 'x': spr.screenCenter(X);
				case 'y': spr.screenCenter(Y);
				default:  spr.screenCenter(XY);
			}
		});

		Lua_helper.add_callback(lua, "objectsOverlap", function(obj1:String, obj2:String):Bool
		{
			var a:FlxSprite = game.getLuaObject(obj1) != null ? game.getLuaObject(obj1) : Reflect.getProperty(LuaUtils.getTargetInstance(), obj1);
			var b:FlxSprite = game.getLuaObject(obj2) != null ? game.getLuaObject(obj2) : Reflect.getProperty(LuaUtils.getTargetInstance(), obj2);
			return a != null && b != null && FlxG.overlap(a, b);
		});

		Lua_helper.add_callback(lua, "getPixelColor", function(obj:String, x:Int, y:Int):Int
		{
			var spr:FlxSprite = _getSpriteFromVar(obj);
			return spr != null ? spr.pixels.getPixel32(x, y) : FlxColor.BLACK;
		});

		Lua_helper.add_callback(lua, "getObjectOrder", function(obj:String):Int
		{
			var o:FlxBasic = _getBasicFromVar(obj);
			if (o != null) return LuaUtils.getTargetInstance().members.indexOf(o);
			luaTrace('getObjectOrder: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
			return -1;
		});

		Lua_helper.add_callback(lua, "setObjectOrder", function(obj:String, position:Int):Void
		{
			var o:FlxBasic = _getBasicFromVar(obj);
			if (o != null) { LuaUtils.getTargetInstance().remove(o, true); LuaUtils.getTargetInstance().insert(position, o); return; }
			luaTrace('setObjectOrder: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
		});

		Lua_helper.add_callback(lua, "setObjectCamera", function(obj:String, camera:String = ''):Bool
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) { spr.cameras = [LuaUtils.cameraFromString(camera)]; return true; }
			luaTrace('setObjectCamera: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
			return false;
		});

		Lua_helper.add_callback(lua, "setBlendMode", function(obj:String, blend:String = ''):Bool
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) { spr.blend = LuaUtils.blendModeFromString(blend); return true; }
			luaTrace('setBlendMode: Object $obj doesn\'t exist!', false, false, FlxColor.RED);
			return false;
		});

		Lua_helper.add_callback(lua, "setSpriteColor", function(obj:String, color:String):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) spr.color = CoolUtil.colorFromString(color);
		});

		Lua_helper.add_callback(lua, "getSpriteColor", function(obj:String):Int
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			return spr != null ? spr.color : FlxColor.WHITE;
		});

		Lua_helper.add_callback(lua, "setSpriteAngle", function(obj:String, angle:Float):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) spr.angle = angle;
		});

		Lua_helper.add_callback(lua, "getSpriteAngle", function(obj:String):Float
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			return spr != null ? spr.angle : 0;
		});

		Lua_helper.add_callback(lua, "setSpriteAlpha", function(obj:String, alpha:Float):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) spr.alpha = alpha;
		});

		Lua_helper.add_callback(lua, "getSpriteAlpha", function(obj:String):Float
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			return spr != null ? spr.alpha : 1;
		});

		Lua_helper.add_callback(lua, "setSpriteVisible", function(obj:String, visible:Bool):Void
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			if (spr != null) spr.visible = visible;
		});

		Lua_helper.add_callback(lua, "getSpriteVisible", function(obj:String):Bool
		{
			var spr:FlxSprite = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : _getSpriteFromVar(obj);
			return spr != null ? spr.visible : false;
		});

		Lua_helper.add_callback(lua, "setHealthBarColors", function(left:String, right:String):Void
		{
			var lc:Null<FlxColor> = (left  != null && left  != '') ? CoolUtil.colorFromString(left)  : null;
			var rc:Null<FlxColor> = (right != null && right != '') ? CoolUtil.colorFromString(right) : null;
			game.healthBar.setColors(lc, rc);
		});

		Lua_helper.add_callback(lua, "setTimeBarColors", function(left:String, right:String):Void
		{
			var lc:Null<FlxColor> = (left  != null && left  != '') ? CoolUtil.colorFromString(left)  : null;
			var rc:Null<FlxColor> = (right != null && right != '') ? CoolUtil.colorFromString(right) : null;
			game.timeBar.setColors(lc, rc);
		});

		Lua_helper.add_callback(lua, "getMidpointX",        function(v:String):Float return _getMidpoint(v, true,  false));
		Lua_helper.add_callback(lua, "getMidpointY",        function(v:String):Float return _getMidpoint(v, false, false));
		Lua_helper.add_callback(lua, "getGraphicMidpointX", function(v:String):Float return _getMidpoint(v, true,  true));
		Lua_helper.add_callback(lua, "getGraphicMidpointY", function(v:String):Float return _getMidpoint(v, false, true));

		Lua_helper.add_callback(lua, "getScreenPositionX", function(variable:String, ?camera:String):Float
		{
			var spr:FlxSprite = _getSpriteFromVar(variable);
			return spr != null ? spr.getScreenPosition().x : 0;
		});
		Lua_helper.add_callback(lua, "getScreenPositionY", function(variable:String, ?camera:String):Float
		{
			var spr:FlxSprite = _getSpriteFromVar(variable);
			return spr != null ? spr.getScreenPosition().y : 0;
		});

		Lua_helper.add_callback(lua, "luaSpriteExists", function(tag:String):Bool return game.modchartSprites.exists(tag));
		Lua_helper.add_callback(lua, "luaTextExists",   function(tag:String):Bool return game.modchartTexts.exists(tag));
		Lua_helper.add_callback(lua, "luaSoundExists",  function(tag:String):Bool return game.modchartSounds.exists(tag));

		Lua_helper.add_callback(lua, "FlxColor",           function(color:String):Int return FlxColor.fromString(color));
		Lua_helper.add_callback(lua, "getColorFromName",   function(color:String):Int return FlxColor.fromString(color));
		Lua_helper.add_callback(lua, "getColorFromString", function(color:String):Int return FlxColor.fromString(color));
		Lua_helper.add_callback(lua, "getColorFromHex",    function(color:String):Int return FlxColor.fromString('#$color'));
	}

	private function _registerTweenCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "startTween", function(tag:String, vars:String, values:Any = null, duration:Float, options:Any = null):Void
		{
			var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			if (target == null) { luaTrace('startTween: Couldn\'t find object: $vars', false, false, FlxColor.RED); return; }
			if (values == null) { luaTrace('startTween: No values on 2nd argument!',   false, false, FlxColor.RED); return; }
			var myOptions:LuaTweenOptions = LuaUtils.getLuaTween(options);
			game.modchartTweens.set(tag, FlxTween.tween(target, values, duration, {
				type:       myOptions.type,
				ease:       myOptions.ease,
				startDelay: myOptions.startDelay,
				loopDelay:  myOptions.loopDelay,
				onUpdate:   function(twn:FlxTween):Void { if (myOptions.onUpdate   != null) game.callOnLuas(myOptions.onUpdate,   [tag, vars]); },
				onStart:    function(twn:FlxTween):Void { if (myOptions.onStart    != null) game.callOnLuas(myOptions.onStart,    [tag, vars]); },
				onComplete: function(twn:FlxTween):Void
				{
					if (myOptions.onComplete != null) game.callOnLuas(myOptions.onComplete, [tag, vars]);
					if (twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD)
						game.modchartTweens.remove(tag);
				}
			}));
		});

		Lua_helper.add_callback(lua, "doTweenX",     function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String):Void oldTweenFunction(tag, vars, {x: value},     duration, ease, 'doTweenX'));
		Lua_helper.add_callback(lua, "doTweenY",     function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String):Void oldTweenFunction(tag, vars, {y: value},     duration, ease, 'doTweenY'));
		Lua_helper.add_callback(lua, "doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String):Void oldTweenFunction(tag, vars, {angle: value}, duration, ease, 'doTweenAngle'));
		Lua_helper.add_callback(lua, "doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String):Void oldTweenFunction(tag, vars, {alpha: value}, duration, ease, 'doTweenAlpha'));
		Lua_helper.add_callback(lua, "doTweenZoom",  function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String):Void oldTweenFunction(tag, vars, {zoom: value},  duration, ease, 'doTweenZoom'));

		Lua_helper.add_callback(lua, "doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ease:String):Void
		{
			var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
			if (target == null) { luaTrace('doTweenColor: Couldn\'t find object: $vars', false, false, FlxColor.RED); return; }
			var curColor:FlxColor = target.color;
			curColor.alphaFloat   = target.alpha;
			game.modchartTweens.set(tag, FlxTween.color(target, duration, curColor, CoolUtil.colorFromString(targetColor), {
				ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween):Void
				{
					game.modchartTweens.remove(tag);
					game.callOnLuas('onTweenCompleted', [tag, vars]);
				}
			}));
		});

		for (prop in ['X', 'Y', 'Angle', 'Alpha', 'Direction'])
		{
			var p:String = prop.toLowerCase();
			Lua_helper.add_callback(lua, 'noteTween$prop', function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String):Void
			{
				LuaUtils.cancelTween(tag);
				if (note < 0) note = 0;
				var strum:StrumNote = game.strumLineNotes.members[note % game.strumLineNotes.length];
				if (strum == null) return;
				var tweenObj:Dynamic = {};
				Reflect.setField(tweenObj, p, value);
				game.modchartTweens.set(tag, FlxTween.tween(strum, tweenObj, duration, {
					ease: LuaUtils.getTweenEaseByString(ease),
					onComplete: function(twn:FlxTween):Void
					{
						game.callOnLuas('onTweenCompleted', [tag]);
						game.modchartTweens.remove(tag);
					}
				}));
			});
		}

		Lua_helper.add_callback(lua, "cancelTween", function(tag:String):Void { LuaUtils.cancelTween(tag); });

		Lua_helper.add_callback(lua, "runTimer", function(tag:String, time:Float = 1, loops:Int = 1):Void
		{
			LuaUtils.cancelTimer(tag);
			game.modchartTimers.set(tag, new FlxTimer().start(time, function(tmr:FlxTimer):Void
			{
				if (tmr.finished) game.modchartTimers.remove(tag);
				game.callOnLuas('onTimerCompleted', [tag, tmr.loops, tmr.loopsLeft]);
			}, loops));
		});

		Lua_helper.add_callback(lua, "cancelTimer", function(tag:String):Void { LuaUtils.cancelTimer(tag); });
	}

	private function _registerSoundCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "playMusic", function(sound:String, volume:Float = 1, loop:Bool = false):Void
		{
			FlxG.sound.playMusic(Paths.music(sound), volume, loop);
		});

		Lua_helper.add_callback(lua, "playSound", function(sound:String, volume:Float = 1, ?tag:String = null):Void
		{
			if (tag != null && tag.length > 0)
			{
				tag = tag.replace('.', '');
				if (game.modchartSounds.exists(tag)) game.modchartSounds.get(tag).stop();
				game.modchartSounds.set(tag, FlxG.sound.play(Paths.sound(sound), volume, false, null, true, function():Void
				{
					game.modchartSounds.remove(tag);
					game.callOnLuas('onSoundFinished', [tag]);
				}));
				return;
			}
			FlxG.sound.play(Paths.sound(sound), volume);
		});

		Lua_helper.add_callback(lua, "stopSound",   function(tag:String):Void { if (tag != null && tag.length > 1 && game.modchartSounds.exists(tag)) { game.modchartSounds.get(tag).stop();  game.modchartSounds.remove(tag); } });
		Lua_helper.add_callback(lua, "pauseSound",  function(tag:String):Void { if (tag != null && tag.length > 1 && game.modchartSounds.exists(tag))   game.modchartSounds.get(tag).pause(); });
		Lua_helper.add_callback(lua, "resumeSound", function(tag:String):Void { if (tag != null && tag.length > 1 && game.modchartSounds.exists(tag))   game.modchartSounds.get(tag).play();  });

		Lua_helper.add_callback(lua, "soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1):Void
		{
			if (tag == null || tag.length < 1) FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			else if (game.modchartSounds.exists(tag)) game.modchartSounds.get(tag).fadeIn(duration, fromValue, toValue);
		});

		Lua_helper.add_callback(lua, "soundFadeOut", function(tag:String, duration:Float, toValue:Float = 0):Void
		{
			if (tag == null || tag.length < 1) FlxG.sound.music.fadeOut(duration, toValue);
			else if (game.modchartSounds.exists(tag)) game.modchartSounds.get(tag).fadeOut(duration, toValue);
		});

		Lua_helper.add_callback(lua, "soundFadeCancel", function(tag:String):Void
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music.fadeTween != null) FlxG.sound.music.fadeTween.cancel();
				return;
			}
			if (game.modchartSounds.exists(tag))
			{
				var s:FlxSound = game.modchartSounds.get(tag);
				if (s.fadeTween != null) { s.fadeTween.cancel(); game.modchartSounds.remove(tag); }
			}
		});

		Lua_helper.add_callback(lua, "getSoundVolume", function(tag:String):Float
		{
			if (tag == null || tag.length < 1) return FlxG.sound.music != null ? FlxG.sound.music.volume : 0;
			return game.modchartSounds.exists(tag) ? game.modchartSounds.get(tag).volume : 0;
		});

		Lua_helper.add_callback(lua, "setSoundVolume", function(tag:String, value:Float):Void
		{
			if (tag == null || tag.length < 1) { if (FlxG.sound.music != null) FlxG.sound.music.volume = value; return; }
			if (game.modchartSounds.exists(tag)) game.modchartSounds.get(tag).volume = value;
		});

		Lua_helper.add_callback(lua, "getSoundTime", function(tag:String):Float
		{
			return (tag != null && tag.length > 0 && game.modchartSounds.exists(tag)) ? game.modchartSounds.get(tag).time : 0;
		});

		Lua_helper.add_callback(lua, "setSoundTime", function(tag:String, value:Float):Void
		{
			if (tag == null || tag.length < 1 || !game.modchartSounds.exists(tag)) return;
			var s:FlxSound = game.modchartSounds.get(tag);
			if (s == null) return;
			var wasPlaying:Bool = s.playing;
			s.pause();
			s.time = value;
			if (wasPlaying) s.play();
		});

		#if FLX_PITCH
		Lua_helper.add_callback(lua, "getSoundPitch", function(tag:String):Float
		{
			return (tag != null && tag.length > 0 && game.modchartSounds.exists(tag)) ? game.modchartSounds.get(tag).pitch : 0;
		});

		Lua_helper.add_callback(lua, "setSoundPitch", function(tag:String, value:Float, doPause:Bool = false):Void
		{
			if (tag == null || tag.length < 1 || !game.modchartSounds.exists(tag)) return;
			var s:FlxSound = game.modchartSounds.get(tag);
			if (s == null) return;
			var wasPlaying:Bool = s.playing;
			if (doPause) s.pause();
			s.pitch = value;
			if (doPause && wasPlaying) s.play();
		});
		#end
	}

	private function _registerCameraCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "cameraSetTarget", function(target:String):Bool
		{
			var isDad:Bool = target == 'dad';
			game.moveCamera(isDad);
			return isDad;
		});

		Lua_helper.add_callback(lua, "cameraShake", function(camera:String, intensity:Float, duration:Float):Void
		{
			LuaUtils.cameraFromString(camera).shake(intensity, duration);
		});

		Lua_helper.add_callback(lua, "cameraFlash", function(camera:String, color:String, duration:Float, forced:Bool):Void
		{
			LuaUtils.cameraFromString(camera).flash(CoolUtil.colorFromString(color), duration, null, forced);
		});

		Lua_helper.add_callback(lua, "cameraFade", function(camera:String, color:String, duration:Float, forced:Bool):Void
		{
			LuaUtils.cameraFromString(camera).fade(CoolUtil.colorFromString(color), duration, false, null, forced);
		});

		Lua_helper.add_callback(lua, "setCameraZoom", function(value:Float, ?camera:String = 'game'):Void
		{
			LuaUtils.cameraFromString(camera).zoom = value;
		});

		Lua_helper.add_callback(lua, "getCameraZoom", function(?camera:String = 'game'):Float
		{
			return LuaUtils.cameraFromString(camera).zoom;
		});

		Lua_helper.add_callback(lua, "tweenCameraZoom", function(zoom:Float, duration:Float, ease:String, ?camera:String = 'game', ?tag:String = 'camZoom'):Void
		{
			LuaUtils.cancelTween(tag);
			var cam:FlxCamera = LuaUtils.cameraFromString(camera);
			game.modchartTweens.set(tag, FlxTween.tween(cam, {zoom: zoom}, duration, {
				ease: LuaUtils.getTweenEaseByString(ease),
				onComplete: function(twn:FlxTween):Void
				{
					game.modchartTweens.remove(tag);
					game.callOnLuas('onTweenCompleted', [tag]);
				}
			}));
		});

		Lua_helper.add_callback(lua, "setCameraFollowLerp", function(value:Float):Void
		{
			FlxG.camera.followLerp = value;
		});

		Lua_helper.add_callback(lua, "getMouseX", function(camera:String):Float
		{
			return FlxG.mouse.getScreenPosition(LuaUtils.cameraFromString(camera)).x;
		});

		Lua_helper.add_callback(lua, "getMouseY", function(camera:String):Float
		{
			return FlxG.mouse.getScreenPosition(LuaUtils.cameraFromString(camera)).y;
		});
	}

	private function _registerInputCallbacks():Void
	{
		Lua_helper.add_callback(lua, "mouseClicked", function(button:String):Bool
		{
			return switch (button) {
				case 'middle': FlxG.mouse.justPressedMiddle;
				case 'right':  FlxG.mouse.justPressedRight;
				default:       FlxG.mouse.justPressed;
			};
		});

		Lua_helper.add_callback(lua, "mousePressed", function(button:String):Bool
		{
			return switch (button) {
				case 'middle': FlxG.mouse.pressedMiddle;
				case 'right':  FlxG.mouse.pressedRight;
				default:       FlxG.mouse.pressed;
			};
		});

		Lua_helper.add_callback(lua, "mouseReleased", function(button:String):Bool
		{
			return switch (button) {
				case 'middle': FlxG.mouse.justReleasedMiddle;
				case 'right':  FlxG.mouse.justReleasedRight;
				default:       FlxG.mouse.justReleased;
			};
		});

		#if !FLX_NO_KEYBOARD
		Lua_helper.add_callback(lua, "keyPressed", function(key:String):Bool
		{
			return FlxG.keys.checkStatus(FlxKey.fromString(key), PRESSED);
		});

		Lua_helper.add_callback(lua, "keyJustPressed", function(key:String):Bool
		{
			return FlxG.keys.checkStatus(FlxKey.fromString(key), JUST_PRESSED);
		});

		Lua_helper.add_callback(lua, "keyJustReleased", function(key:String):Bool
		{
			return FlxG.keys.checkStatus(FlxKey.fromString(key), JUST_RELEASED);
		});
		#end
	}

	private function _registerUtilCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "initLuaShader", function(name:String):Bool
		{
			return initLuaShader(name);
		});
	}

	private function _registerNewCallbacks(game:PlayState):Void
	{
		Lua_helper.add_callback(lua, "getEngineVersion", function():String
		{
			return MainMenuState.psychEngineVersion.trim();
		});

		Lua_helper.add_callback(lua, "getPlatform", function():String
		{
			return backend.system.Main.platform;
		});

		Lua_helper.add_callback(lua, "isOnline", function():Bool
		{
			return online.Online.isConnected;
		});

		Lua_helper.add_callback(lua, "formatFloat", function(value:Float, decimals:Int = 2):String
		{
			return Std.string(Math.round(value * Math.pow(10, decimals)) / Math.pow(10, decimals));
		});

		Lua_helper.add_callback(lua, "clampValue", function(value:Float, min:Float, max:Float):Float
		{
			return FlxMath.bound(value, min, max);
		});

		Lua_helper.add_callback(lua, "lerpValue", function(from:Float, to:Float, ratio:Float):Float
		{
			return FlxMath.lerp(from, to, ratio);
		});

		Lua_helper.add_callback(lua, "randomInt", function(min:Int, max:Int):Int
		{
			return FlxG.random.int(min, max);
		});

		Lua_helper.add_callback(lua, "randomFloat", function(min:Float, max:Float):Float
		{
			return FlxG.random.float(min, max);
		});

		Lua_helper.add_callback(lua, "randomBool", function(chance:Float = 50):Bool
		{
			return FlxG.random.bool(chance);
		});

		Lua_helper.add_callback(lua, "getProperty", function(obj:String, prop:String):Dynamic
		{
			var spr:Dynamic = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : LuaUtils.getObjectDirectly(obj);
			if (spr == null) return null;
			return Reflect.getProperty(spr, prop);
		});

		Lua_helper.add_callback(lua, "setProperty", function(obj:String, prop:String, value:Dynamic):Void
		{
			var spr:Dynamic = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : LuaUtils.getObjectDirectly(obj);
			if (spr != null) Reflect.setProperty(spr, prop, value);
		});

		Lua_helper.add_callback(lua, "callMethod", function(obj:String, method:String, ?args:Array<Dynamic> = null):Dynamic
		{
			if (api.APISystem.isCallBlocked('Reflect.callMethod')) return null;
			var spr:Dynamic = game.getLuaObject(obj) != null ? game.getLuaObject(obj) : LuaUtils.getObjectDirectly(obj);
			if (spr == null) return null;
			var func:Dynamic = Reflect.getProperty(spr, method);
			if (func == null) return null;
			return Reflect.callMethod(spr, func, args != null ? args : []);
		});

		Lua_helper.add_callback(lua, "showPopup", function(message:String, title:String = 'Notice'):Void
		{
			CoolUtil.showPopUp(message, title);
		});

		Lua_helper.add_callback(lua, "getCurrentState", function():String
		{
			return Type.getClassName(Type.getClass(FlxG.state));
		});

		Lua_helper.add_callback(lua, "isInPlayState", function():Bool
		{
			return Std.isOfType(FlxG.state, PlayState);
		});

		Lua_helper.add_callback(lua, "getFramerate", function():Int
		{
			return FlxG.drawFramerate;
		});

		Lua_helper.add_callback(lua, "setFramerate", function(value:Int):Void
		{
			FlxG.updateFramerate = value;
			FlxG.drawFramerate   = value;
		});

		Lua_helper.add_callback(lua, "isMobile", function():Bool
		{
			return #if mobile true #else false #end;
		});

		Lua_helper.add_callback(lua, "isAndroid", function():Bool
		{
			return #if android true #else false #end;
		});
	}

	private function _loadScript():Void
	{
		try
		{
			var isString:Bool  = !FileSystem.exists(scriptName);
			var result:Dynamic = isString ? LuaL.dostring(lua, scriptName) : LuaL.dofile(lua, scriptName);
			var resultStr:String = Lua.tostring(lua, result);

			if (resultStr != null && result != 0)
			{
				#if (windows || mobile || js || wasm)
				CoolUtil.showPopUp(resultStr, 'Error on lua script!');
				#else
				luaTrace('$scriptName\n$resultStr', true, false, FlxColor.RED);
				#end
				lua = null;
				return;
			}

			if (isString) scriptName = 'unknown';
		}
		catch (e:Dynamic)
		{
			return;
		}

		call('onCreate', []);
	}

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		if (closed) return LuaUtils.Function_Continue;

		lastCalledFunction = func;
		lastCalledScript   = this;

		try
		{
			if (lua == null) return LuaUtils.Function_Continue;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);

			if (type != Lua.LUA_TFUNCTION)
			{
				if (type > Lua.LUA_TNIL)
					luaTrace('ERROR ($func): attempt to call a ${LuaUtils.typeToString(type)} value', false, false, FlxColor.RED);
				Lua.pop(lua, 1);
				return LuaUtils.Function_Continue;
			}

			for (arg in args) Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);

			if (status != Lua.LUA_OK)
			{
				luaTrace('ERROR ($func): ${getErrorMessage(status)}', false, false, FlxColor.RED);
				return LuaUtils.Function_Continue;
			}

			var result:Dynamic = cast Convert.fromLua(lua, -1);
			if (result == null) result = LuaUtils.Function_Continue;

			Lua.pop(lua, 1);
			if (closed) stop();
			return result;
		}
		catch (e:Dynamic) {}

		return LuaUtils.Function_Continue;
	}

	public function set(variable:String, data:Dynamic):Void
	{
		if (lua == null) return;
		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
	}

	public function stop():Void
	{
		closed = true;
		if (lua == null) return;
		Lua.close(lua);
		lua = null;
		#if HSCRIPT_ALLOWED
		if (hscript != null)
		{
			hscript.destroy();
			hscript = null;
		}
		#end
	}

	private function oldTweenFunction(tag:String, vars:String, tweenValue:Any, duration:Float, ease:String, funcName:String):Void
	{
		var target:Dynamic = LuaUtils.tweenPrepare(tag, vars);
		if (target == null) { luaTrace('$funcName: Couldn\'t find object: $vars', false, false, FlxColor.RED); return; }
		PlayState.instance.modchartTweens.set(tag, FlxTween.tween(target, tweenValue, duration, {
			ease: LuaUtils.getTweenEaseByString(ease),
			onComplete: function(twn:FlxTween):Void
			{
				PlayState.instance.modchartTweens.remove(tag);
				PlayState.instance.callOnLuas('onTweenCompleted', [tag, vars]);
			}
		}));
	}

	private function _getSpriteFromVar(variable:String):FlxSprite
	{
		var split:Array<String> = variable.split('.');
		var spr:FlxSprite = LuaUtils.getObjectDirectly(split[0]);
		if (split.length > 1)
			spr = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		return spr;
	}

	private function _getBasicFromVar(variable:String):FlxBasic
	{
		var split:Array<String> = variable.split('.');
		var obj:FlxBasic = LuaUtils.getObjectDirectly(split[0]);
		if (split.length > 1)
			obj = LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		return obj;
	}

	private function _getMidpoint(variable:String, getX:Bool, graphic:Bool):Float
	{
		var spr:FlxSprite = _getSpriteFromVar(variable);
		if (spr == null) return 0;
		var point = graphic ? spr.getGraphicMidpoint() : spr.getMidpoint();
		return getX ? point.x : point.y;
	}

	public static function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE):Void
	{
		if (!ignoreCheck && !getBool('luaDebugMode')) return;
		if (deprecated && !getBool('luaDeprecatedWarnings')) return;
		PlayState.instance.addTextToDebug(text, color);
	}

	public static function getBool(variable:String):Bool
	{
		if (lastCalledScript == null) return false;
		var lua:State = lastCalledScript.lua;
		if (lua == null) return false;
		Lua.getglobal(lua, variable);
		var result:Dynamic = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);
		return result == 'true';
	}

	public function findScript(scriptFile:String, ext:String = '.lua'):String
	{
		if (!scriptFile.endsWith(ext)) scriptFile += ext;
		var preloadPath:String = Paths.getSharedPath(scriptFile);
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(scriptFile);
		if (FileSystem.exists(scriptFile))  return scriptFile;
		if (FileSystem.exists(path))        return path;
		if (FileSystem.exists(preloadPath)) return preloadPath;
		#else
		if (Assets.exists(preloadPath)) return preloadPath;
		#end
		return null;
	}

	public function getErrorMessage(status:Int):String
	{
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		if (v != null) v = v.trim();
		if (v == null || v == '')
			return switch (status) {
				case Lua.LUA_ERRRUN: "Runtime Error";
				case Lua.LUA_ERRMEM: "Memory Allocation Error";
				case Lua.LUA_ERRERR: "Critical Error";
				default:             "Unknown Error";
			};
		return v;
	}

	public function addLocalCallback(name:String, myFunction:Dynamic):Void
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, null);
	}

	public function initLuaShader(name:String):Bool
	{
		if (!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if (runtimeShaders.exists(name)) return true;

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods('${Mods.currentModDirectory}/shaders/'));
		for (mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods('$mod/shaders/'));

		for (folder in foldersToCheck)
		{
			if (!FileSystem.exists(folder)) continue;
			var frag:String = FileSystem.exists(folder + name + '.frag') ? File.getContent(folder + name + '.frag') : null;
			var vert:String = FileSystem.exists(folder + name + '.vert') ? File.getContent(folder + name + '.vert') : null;
			if (frag != null || vert != null)
			{
				runtimeShaders.set(name, [frag, vert]);
				return true;
			}
		}
		luaTrace('Missing shader $name .frag AND .vert files!', false, false, FlxColor.RED);
		#else
		luaTrace('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}
}
#end