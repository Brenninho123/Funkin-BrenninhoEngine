package backend;

import openfl.utils.Assets;
import haxe.Json;
import backend.Song;

typedef StageCharacterData =
{
	var position:Array<Float>;
	var ?flipX:Bool;
	var ?scale:Float;
	var ?scrollFactor:Array<Float>;
	var ?alpha:Float;
	var ?angle:Float;
	var ?cameraOffset:Array<Float>;
}

typedef StageLightingData =
{
	var ?ambientColor:String;
	var ?ambientAlpha:Float;
	var ?vignetteColor:String;
	var ?vignetteAlpha:Float;
	var ?bloom:Bool;
	var ?bloomStrength:Float;
}

typedef StageWeatherData =
{
	var type:String;
	var ?intensity:Float;
	var ?color:String;
	var ?wind:Float;
}

typedef StageLayerData =
{
	var image:String;
	var ?x:Float;
	var ?y:Float;
	var ?scrollX:Float;
	var ?scrollY:Float;
	var ?alpha:Float;
	var ?scale:Float;
	var ?angle:Float;
	var ?color:String;
	var ?blend:String;
	var ?animated:Bool;
	var ?animPrefix:String;
	var ?animFps:Int;
	var ?animLoop:Bool;
	var ?above:String;
	var ?flipX:Bool;
	var ?flipY:Bool;
	var ?antialiasing:Bool;
}

typedef StageSoundData =
{
	var file:String;
	var ?volume:Float;
	var ?loop:Bool;
	var ?fadeIn:Float;
}

typedef StageScriptData =
{
	var ?lua:String;
	var ?hx:String;
}

typedef StageFile =
{
	var directory:String;
	var defaultZoom:Float;
	var isPixelStage:Bool;
	var stageUI:String;

	var boyfriend:Array<Dynamic>;
	var girlfriend:Array<Dynamic>;
	var opponent:Array<Dynamic>;
	var hide_girlfriend:Bool;

	var camera_boyfriend:Array<Float>;
	var camera_opponent:Array<Float>;
	var camera_girlfriend:Array<Float>;
	var camera_speed:Null<Float>;

	var ?boyfriendData:StageCharacterData;
	var ?girlfriendData:StageCharacterData;
	var ?opponentData:StageCharacterData;

	var ?camera_boyfriend_lerp:Float;
	var ?camera_opponent_lerp:Float;
	var ?camera_girlfriend_lerp:Float;

	var ?camera_zoom_strength:Float;
	var ?beat_zoom_multiplier:Float;
	var ?beat_zoom_camera:Float;

	var ?bg_color:String;
	var ?skin:String;

	var ?layers:Array<StageLayerData>;
	var ?foreground:Array<StageLayerData>;

	var ?lighting:StageLightingData;
	var ?weather:StageWeatherData;
	var ?ambientSound:StageSoundData;

	var ?scripts:StageScriptData;

	var ?pixelZoom:Float;
	var ?noAntialiasing:Bool;
	var ?hideHud:Bool;
	var ?countdownSkin:String;
	var ?noteSkin:String;
}

class StageData
{
	static final _VANILLA_STAGES:Map<String, String> = [
		'spookeez'        => 'spooky',
		'south'           => 'spooky',
		'monster'         => 'spooky',
		'pico'            => 'philly',
		'blammed'         => 'philly',
		'philly'          => 'philly',
		'philly-nice'     => 'philly',
		'milf'            => 'limo',
		'satin-panties'   => 'limo',
		'high'            => 'limo',
		'cocoa'           => 'mall',
		'eggnog'          => 'mall',
		'winter-horrorland' => 'mallEvil',
		'senpai'          => 'school',
		'roses'           => 'school',
		'thorns'          => 'schoolEvil',
		'ugh'             => 'tank',
		'guns'            => 'tank',
		'stress'          => 'tank'
	];

	public static var forceNextDirectory:String = null;

	public static function dummy():StageFile
	{
		return {
			directory:       '',
			defaultZoom:     0.9,
			isPixelStage:    false,
			stageUI:         'normal',

			boyfriend:       [770, 100],
			girlfriend:      [400, 130],
			opponent:        [100, 100],
			hide_girlfriend: false,

			camera_boyfriend: [0, 0],
			camera_opponent:  [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed:     1,

			boyfriendData:    null,
			girlfriendData:   null,
			opponentData:     null,

			camera_boyfriend_lerp:  null,
			camera_opponent_lerp:   null,
			camera_girlfriend_lerp: null,

			camera_zoom_strength:  0.015,
			beat_zoom_multiplier:  1.0,
			beat_zoom_camera:      1.0,

			bg_color:       null,
			skin:           null,
			layers:         [],
			foreground:     [],

			lighting:       null,
			weather:        null,
			ambientSound:   null,
			scripts:        null,

			pixelZoom:      6.0,
			noAntialiasing: false,
			hideHud:        false,
			countdownSkin:  null,
			noteSkin:       null
		};
	}

	public static function loadDirectory(SONG:SwagSong):Void
	{
		var stage:String = _resolveStage(SONG);
		var stageFile:StageFile = getStageFile(stage);
		forceNextDirectory = stageFile != null ? stageFile.directory : '';
	}

	public static function getStageFile(stage:String):Null<StageFile>
	{
		var raw:Null<String> = _readStageJson(stage);
		if (raw == null || raw.length == 0) return null;

		try
		{
			var parsed:StageFile = cast tjson.TJSON.parse(raw);
			return _applyDefaults(parsed);
		}
		catch (e:Dynamic) { return null; }
	}

	public static function vanillaSongStage(songName:String):String
	{
		var key:String = songName.toLowerCase().replace(' ', '-');
		return _VANILLA_STAGES.exists(key) ? _VANILLA_STAGES.get(key) : 'stage';
	}

	public static function getCharacterPos(data:StageFile, char:String):Array<Dynamic>
	{
		return switch (char.toLowerCase())
		{
			case 'bf' | 'boyfriend': data.boyfriend;
			case 'gf' | 'girlfriend': data.girlfriend;
			case 'dad' | 'opponent': data.opponent;
			default: [0, 0];
		};
	}

	public static function getCameraPos(data:StageFile, char:String):Array<Float>
	{
		return switch (char.toLowerCase())
		{
			case 'bf' | 'boyfriend': data.camera_boyfriend ?? [0, 0];
			case 'gf' | 'girlfriend': data.camera_girlfriend ?? [0, 0];
			case 'dad' | 'opponent': data.camera_opponent ?? [0, 0];
			default: [0, 0];
		};
	}

	public static function getCharacterData(data:StageFile, char:String):Null<StageCharacterData>
	{
		return switch (char.toLowerCase())
		{
			case 'bf' | 'boyfriend': data.boyfriendData;
			case 'gf' | 'girlfriend': data.girlfriendData;
			case 'dad' | 'opponent': data.opponentData;
			default: null;
		};
	}

	public static function getLayers(data:StageFile, ?above:String):Array<StageLayerData>
	{
		var src:Array<StageLayerData> = data.layers ?? [];
		if (above == null) return src.copy();
		return src.filter(function(l:StageLayerData):Bool { return l.above == above; });
	}

	public static function getForeground(data:StageFile):Array<StageLayerData>
	{
		return (data.foreground ?? []).copy();
	}

	public static function hasScript(data:StageFile):Bool
	{
		return data.scripts != null && (data.scripts.lua != null || data.scripts.hx != null);
	}

	public static function stageExists(stage:String):Bool
	{
		return _readStageJson(stage) != null;
	}

	private static function _resolveStage(SONG:SwagSong):String
	{
		if (SONG.stage != null && SONG.stage.length > 0) return SONG.stage;
		if (SONG.song != null) return vanillaSongStage(SONG.song);
		return 'stage';
	}

	private static function _readStageJson(stage:String):Null<String>
	{
		var path:String = Paths.getSharedPath('stages/$stage.json');

		#if MODS_ALLOWED
		var modPath:String = Paths.modFolders('stages/$stage.json');
		if (FileSystem.exists(modPath))  return File.getContent(modPath);
		if (FileSystem.exists(path))     return File.getContent(path);
		#else
		if (Assets.exists(path))         return Assets.getText(path);
		#end

		return null;
	}

	private static function _applyDefaults(data:StageFile):StageFile
	{
		if (data.layers    == null) data.layers    = [];
		if (data.foreground == null) data.foreground = [];
		if (data.camera_boyfriend  == null) data.camera_boyfriend  = [0, 0];
		if (data.camera_opponent   == null) data.camera_opponent   = [0, 0];
		if (data.camera_girlfriend == null) data.camera_girlfriend = [0, 0];
		if (data.camera_speed      == null) data.camera_speed      = 1.0;
		if (data.stageUI           == null || data.stageUI.length == 0) data.stageUI = 'normal';
		if (data.pixelZoom         == null) data.pixelZoom         = 6.0;
		if (data.camera_zoom_strength == null) data.camera_zoom_strength = 0.015;
		if (data.beat_zoom_multiplier == null) data.beat_zoom_multiplier = 1.0;
		if (data.beat_zoom_camera     == null) data.beat_zoom_camera     = 1.0;
		return data;
	}
}
