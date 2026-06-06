package debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.system.System as OpenFlSystem;

#if cpp
#if windows
@:cppFileCode('
#include <windows.h>
#include <psapi.h>
')
#elseif (ios || mac)
@:cppFileCode('#include <mach-o/arch.h>')
@:cppFileCode('#include <sys/sysctl.h>')
#else
@:headerInclude('sys/utsname.h')
@:headerInclude('sys/sysinfo.h')
#end
#end

class FPSCounter extends Sprite
{
	public var currentFPS(default, null):Int = 0;

	private var _textField:TextField;
	private var _bg:Shape;
	private var _times:Array<Float>  = [];
	private var _deltaTimeout:Float  = 0.0;
	private var _systemName:String   = '';
	private var _totalRAM:String     = '';
	private var _updateRamTimer:Float = 0.0;

	static final RAM_UPDATE_INTERVAL:Float = 5000;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFF)
	{
		super();

		_systemName = _detectSystem();
		_totalRAM   = _getTotalRAM();

		_bg = new Shape();
		addChild(_bg);

		_textField                   = new TextField();
		_textField.selectable        = false;
		_textField.mouseEnabled      = false;
		_textField.multiline         = true;
		_textField.autoSize          = openfl.text.TextFieldAutoSize.LEFT;
		_textField.defaultTextFormat = new TextFormat('_sans', 13, color);
		_textField.text              = _buildText(0, '0MB');
		addChild(_textField);

		positionFPS(x, y);
		_drawBg();
	}

	override private function __enterFrame(deltaTime:Float):Void
	{
		_deltaTimeout    += deltaTime;
		_updateRamTimer  += deltaTime;

		if (_deltaTimeout > 1000)
		{
			_deltaTimeout = 0.0;
			return;
		}

		if (_updateRamTimer >= RAM_UPDATE_INTERVAL)
		{
			_updateRamTimer = 0.0;
			_totalRAM       = _getTotalRAM();
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
		var mem:Float     = OpenFlSystem.totalMemory;
		var memStr:String = _formatMemory(mem);

		_textField.text = _buildText(currentFPS, memStr);

		var fpsRatio:Float       = FlxG.drawFramerate > 0 ? currentFPS / FlxG.drawFramerate : 0;
		_textField.textColor     = fpsRatio >= 0.8 ? 0xFFFFFFFF
			: fpsRatio >= 0.5    ? 0xFFFFCC00
			: 0xFFFF3333;

		_drawBg();
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1):Void
	{
		scaleX = scaleY  = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;
		this.x           = FlxG.game.x + X;
		this.y           = FlxG.game.y + Y;
	}

	private function _buildText(fps:Int, mem:String):String
	{
		return 'FPS: $fps • Memory: $mem • System: $_systemName • RAM: $_totalRAM';
	}

	private function _drawBg():Void
	{
		var pad:Float = 5;
		var w:Float   = _textField.textWidth + pad * 2 + 10;
		var h:Float   = 20;

		_bg.graphics.clear();
		_bg.graphics.beginFill(0x000000, 0.55);
		_bg.graphics.drawRoundRect(-pad, -2, w, h, 6, 6);
		_bg.graphics.endFill();
	}

	private function _formatMemory(bytes:Float):String
	{
		if (bytes < 1048576)    return '${Math.round(bytes / 1024)}KB';
		if (bytes < 1073741824) return '${Math.round(bytes / 1048576)}MB';
		return '${_round1(bytes / 1073741824)}GB';
	}

	private inline function _round1(v:Float):Float
	{
		return Math.round(v * 10) / 10;
	}

	private function _detectSystem():String
	{
		#if windows return 'Windows'; #end
		#if mac     return 'macOS';   #end
		#if linux   return 'Linux';   #end
		#if android return 'Android'; #end
		#if ios     return 'iOS';     #end
		#if html5   return 'Web';     #end
		return 'Unknown';
	}

	private function _getTotalRAM():String
	{
		#if cpp
		return _getTotalRAMNative();
		#elseif html5
		return 'N/A';
		#else
		return 'N/A';
		#end
	}

	#if cpp
	#if windows
	@:functionCode('
		MEMORYSTATUSEX memStatus;
		memStatus.dwLength = sizeof(memStatus);
		GlobalMemoryStatusEx(&memStatus);
		double totalGB = (double)memStatus.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
		char buf[32];
		snprintf(buf, sizeof(buf), "%.1fGB", totalGB);
		return ::String(buf);
	')
	private function _getTotalRAMNative():String { return 'N/A'; }

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
	@:noCompletion
	private function getArch():String { return 'Unknown'; }

	#elseif (ios || mac)
	@:functionCode('
		int64_t memSize = 0;
		size_t len = sizeof(memSize);
		sysctlbyname("hw.memsize", &memSize, &len, NULL, 0);
		double totalGB = (double)memSize / (1024.0 * 1024.0 * 1024.0);
		char buf[32];
		snprintf(buf, sizeof(buf), "%.1fGB", totalGB);
		return ::String(buf);
	')
	private function _getTotalRAMNative():String { return 'N/A'; }

	@:functionCode('
		const NXArchInfo *archInfo = NXGetLocalArchInfo();
		return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
	')
	@:noCompletion
	private function getArch():String { return 'Unknown'; }

	#else
	@:functionCode('
		struct sysinfo info;
		sysinfo(&info);
		double totalGB = (double)info.totalram * info.mem_unit / (1024.0 * 1024.0 * 1024.0);
		char buf[32];
		snprintf(buf, sizeof(buf), "%.1fGB", totalGB);
		return ::String(buf);
	')
	private function _getTotalRAMNative():String { return 'N/A'; }

	@:functionCode('
		struct utsname osInfo{};
		uname(&osInfo);
		return ::String(osInfo.machine);
	')
	@:noCompletion
	private function getArch():String { return 'Unknown'; }
	#end
	#end
}
