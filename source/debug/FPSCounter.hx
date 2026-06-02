package debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.display.Sprite;
import openfl.system.System as OpenFlSystem;

#if cpp
#if windows
@:cppFileCode('#include <windows.h>')
#elseif (ios || mac)
@:cppFileCode('#include <mach-o/arch.h>')
#else
@:headerInclude('sys/utsname.h')
#end
#end

class FPSCounter extends Sprite
{
	public var currentFPS(default, null):Int = 0;

	private var _textField:TextField;
	private var _bg:openfl.display.Shape;
	private var _times:Array<Float> = [];
	private var _deltaTimeout:Float = 0.0;
	private var _systemName:String  = '';

	public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFF)
	{
		super();

		_systemName = _detectSystem();

		_bg = new openfl.display.Shape();
		addChild(_bg);

		_textField = new TextField();
		_textField.selectable   = false;
		_textField.mouseEnabled = false;
		_textField.multiline    = true;
		_textField.defaultTextFormat = new TextFormat('_sans', 13, color);
		_textField.width  = 420;
		_textField.height = 22;
		_textField.text   = 'FPS: 0 • Memory: 0MB • System: $_systemName';
		addChild(_textField);

		positionFPS(x, y);
		_drawBg();
	}

	@:access(openfl.display.DisplayObject)
	private function __enterFrame(deltaTime:Float):Void
	{
		_deltaTimeout += deltaTime;

		if (_deltaTimeout > 1000)
		{
			_deltaTimeout = 0.0;
			return;
		}

		final now:Float = haxe.Timer.stamp() * 1000;
		_times.push(now);

		while (_times[0] < now - 1000)
			_times.shift();

		currentFPS = Std.int(Math.min(_times.length, FlxG.updateFramerate));
		updateText();
	}

	public dynamic function updateText():Void
	{
		var mem:Float  = OpenFlSystem.totalMemory;
		var memStr:String = _formatMemory(mem);

		_textField.text = 'FPS: $currentFPS • Memory: $memStr • System: $_systemName';

		var fpsRatio:Float = currentFPS / FlxG.drawFramerate;
		_textField.textColor = fpsRatio >= 0.8 ? 0xFFFFFFFF
			: fpsRatio >= 0.5 ? 0xFFFFCC00
			: 0xFFFF3333;

		_drawBg();
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1):Void
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;
		this.x = FlxG.game.x + X;
		this.y = FlxG.game.y + Y;
	}

	public var visible(get, set):Bool;
	private function get_visible():Bool return super.visible;
	private function set_visible(v:Bool):Bool { super.visible = v; return v; }

	private function _drawBg():Void
	{
		var pad:Float  = 4;
		var w:Float    = _textField.textWidth + pad * 2 + 8;
		var h:Float    = 20;

		_bg.graphics.clear();
		_bg.graphics.beginFill(0x000000, 0.55);
		_bg.graphics.drawRoundRect(-pad, -2, w, h, 6, 6);
		_bg.graphics.endFill();
	}

	private function _formatMemory(bytes:Float):String
	{
		if (bytes < 1048576)    return '${Math.round(bytes / 1024)}KB';
		if (bytes < 1073741824) return '${Math.round(bytes / 1048576)}MB';
		return '${Math.round(bytes / 1073741824)}GB';
	}

	private function _detectSystem():String
	{
		#if windows  return 'Windows'; #end
		#if mac      return 'macOS';   #end
		#if linux    return 'Linux';   #end
		#if android  return 'Android'; #end
		#if ios      return 'iOS';     #end
		#if html5    return 'Web';     #end
		return 'Unknown';
	}

	#if cpp
	#if windows
	@:functionCode('
		SYSTEM_INFO osInfo;
		GetSystemInfo(&osInfo);
		switch (osInfo.wProcessorArchitecture)
		{
			case 9:  return ::String("x86_64");
			case 5:  return ::String("ARM");
			case 12: return ::String("ARM64");
			case 6:  return ::String("IA-64");
			case 0:  return ::String("x86");
			default: return ::String("Unknown");
		}
	')
	#elseif (ios || mac)
	@:functionCode('
		const NXArchInfo *archInfo = NXGetLocalArchInfo();
		return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
	')
	#else
	@:functionCode('
		struct utsname osInfo{};
		uname(&osInfo);
		return ::String(osInfo.machine);
	')
	#end
	@:noCompletion
	private function getArch():String
	{
		return 'Unknown';
	}
	#end
}