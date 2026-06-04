package mobile.backend;

import haxe.ds.Map;
import haxe.Json;
import haxe.io.Path;
import openfl.utils.Assets;
import flixel.util.FlxSave;

class MobileData
{
	public static var actionModes:Map<String, TouchButtonsData> = new Map();
	public static var dpadModes:Map<String, TouchButtonsData>   = new Map();
	public static var extraActions:Map<String, ExtraActions>    = new Map();

	public static var mode(get, set):Int;
	public static var forcedMode:Null<Int>;
	public static var save:FlxSave;

	public static function init():Void
	{
		save = new FlxSave();
		save.bind('MobileControls', CoolUtil.getSavePath());

		readDirectory(Paths.getSharedPath('mobile/DPadModes'),    dpadModes);
		readDirectory(Paths.getSharedPath('mobile/ActionModes'),  actionModes);

		#if MODS_ALLOWED
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'mobile/'))
		{
			readDirectory(Path.join([folder, 'DPadModes']),   dpadModes);
			readDirectory(Path.join([folder, 'ActionModes']), actionModes);
		}
		#end

		for (data in ExtraActions.createAll())
			extraActions.set(data.getName(), data);
	}

	public static function setTouchPadCustom(touchPad:TouchPad):Void
	{
		if (save.data.buttons == null)
		{
			save.data.buttons = new Array();
			for (button in touchPad)
				save.data.buttons.push(FlxPoint.get(button.x, button.y));
		}
		else
		{
			var i:Int = 0;
			for (button in touchPad)
			{
				save.data.buttons[i] = FlxPoint.get(button.x, button.y);
				i++;
			}
		}

		save.flush();
	}

	public static function getTouchPadCustom(touchPad:TouchPad):TouchPad
	{
		if (save.data.buttons == null) return touchPad;

		var i:Int = 0;
		for (button in touchPad)
		{
			if (save.data.buttons[i] != null)
			{
				button.x = save.data.buttons[i].x;
				button.y = save.data.buttons[i].y;
			}
			i++;
		}

		return touchPad;
	}

	public static function setButtonsColors(buttonsInstance:Dynamic):Dynamic
	{
		if (buttonsInstance == null) return buttonsInstance;

		var data:Dynamic = ClientPrefs.data.dynamicColors ? ClientPrefs.data : ClientPrefs.defaultData;

		var buttons:Array<Dynamic> = [
			buttonsInstance.buttonLeft,
			buttonsInstance.buttonDown,
			buttonsInstance.buttonUp,
			buttonsInstance.buttonRight
		];

		for (i in 0...buttons.length)
		{
			var button:Dynamic = buttons[i];
			if (button == null) continue;

			var color:Int = data.arrowRGB[i][0];
			button.color  = color;

			if (button.label != null)
			{
				button.label.color = color;
				button.label.updateColorTransform();
			}
		}

		return buttonsInstance;
	}

	public static function readDirectory(folder:String, map:Dynamic):Void
	{
		folder = folder.contains(':') ? folder.split(':')[1] : folder;

		#if MODS_ALLOWED
		if (!FileSystem.exists(folder)) return;
		#end

		for (file in Paths.readDirectory(folder))
		{
			var fileWithNoLib:String = file.contains(':') ? file.split(':')[1] : file;
			if (Path.extension(fileWithNoLib) != 'json') continue;

			file = Path.join([folder, Path.withoutDirectory(file)]);

			try
			{
				var str:String = #if MODS_ALLOWED File.getContent(file) #else Assets.getText(file) #end;
				var json:TouchButtonsData = cast Json.parse(str);
				var mapKey:String = Path.withoutDirectory(Path.withoutExtension(fileWithNoLib));
				map.set(mapKey, json);
			}
			catch (e:Dynamic) {}
		}
	}

	static function set_mode(mode:Int = 3):Int
	{
		save.data.mobileControlsMode = mode;
		save.flush();
		return mode;
	}

	static function get_mode():Int
	{
		if (forcedMode != null) return forcedMode;

		if (save.data.mobileControlsMode == null)
		{
			save.data.mobileControlsMode = 3;
			save.flush();
		}

		return save.data.mobileControlsMode;
	}
}

typedef TouchButtonsData =
{
	buttons:Array<ButtonsData>
}

typedef ButtonsData =
{
	button:String,
	graphic:String,
	x:Float,
	y:Float,
	color:String
}

enum ExtraActions
{
	SINGLE;
	DOUBLE;
	NONE;
}