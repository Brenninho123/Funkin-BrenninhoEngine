package debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;
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
class FPSCounter extends TextField
{
	public var currentFPS(default, null):Int = 0;

	@:noCompletion private var times:Array<Float> = [];
	private var deltaTimeout:Float = 0.0;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		selectable = false;
		mouseEnabled = false;
		multiline = true;
		defaultTextFormat = new TextFormat('_sans', 14, color);
		width = FlxG.width;
		text = 'FPS: 0';

		positionFPS(x, y);
	}

	private override function __enterFrame(deltaTime:Float):Void
	{
		deltaTimeout += deltaTime;

		if (deltaTimeout > 1000)
		{
			deltaTimeout = 0.0;
			return;
		}

		final now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);

		while (times[0] < now - 1000)
			times.shift();

		currentFPS = Std.int(Math.min(times.length, FlxG.updateFramerate));
		updateText();
	}

	public dynamic function updateText():Void
	{
		text = 'FPS: $currentFPS';
		textColor = (currentFPS < FlxG.drawFramerate * 0.5) ? 0xFFFF0000 : 0xFFFFFFFF;
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1):Void
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;
		x = FlxG.game.x + X;
		y = FlxG.game.y + Y;
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