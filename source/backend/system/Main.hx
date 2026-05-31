package backend.system;

import debug.FPSCounter;
import api.APISystem;
import online.Online;

import flixel.FlxGame;
import flixel.FlxState;
import flixel.FlxCamera;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.system.System as OpenFlSystem;
import lime.system.System as LimeSystem;
import states.TitleState;
import mobile.backend.MobileScaleMode;

#if COPYSTATE_ALLOWED
import states.CopyState;
#end

#if linux
import lime.graphics.Image;
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

#if windows
@:cppFileCode('
#include <windows.h>
#include <winuser.h>
')
#end

class Main extends Sprite
{
	static final GAME_WIDTH:Int        = 1280;
	static final GAME_HEIGHT:Int       = 720;
	static final FRAMERATE:Int         = 60;
	static final SKIP_SPLASH:Bool      = true;
	static final START_FULLSCREEN:Bool = false;

	static final GC_MEMORY_THRESHOLD:Float = 800 * 1024 * 1024;
	static final GC_INTERVAL_MS:Float      = 30000;
	static final FPS_LOW_THRESHOLD:Float   = 0.5;
	static final FPS_CHECK_INTERVAL:Float  = 5000;

	public static var fpsVar:FPSCounter;
	public static final platform:String = #if mobile "Mobile" #else "Desktop" #end;

	private var _gcTimer:Float       = 0.0;
	private var _fpsCheckTimer:Float = 0.0;
	private var _lowFpsStrikes:Int   = 0;
	private var _optimized:Bool      = false;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
		#if cpp
		cpp.NativeGc.enable(true);
		cpp.NativeGc.run(true);
		#end
	}

	public function new()
	{
		super();

		#if android
		StorageUtil.requestPermissions();
		#end

		#if mobile
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end

		backend.CrashHandler.init();
		APISystem.init();
		Online.init();

		#if windows
		@:functionCode('
			setProcessDPIAware();
			DisableProcessWindowsGhosting();
		')
		#end

		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	private function init(?e:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupGame();
	}

	private function setupGame():Void
	{
		var zoom:Float = 1.0;

		#if (openfl <= "9.2.0")
		var stageWidth:Int  = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;
		var ratioX:Float    = stageWidth  / GAME_WIDTH;
		var ratioY:Float    = stageHeight / GAME_HEIGHT;
		zoom                = Math.min(ratioX, ratioY);
		var finalWidth:Int  = Math.ceil(stageWidth  / zoom);
		var finalHeight:Int = Math.ceil(stageHeight / zoom);
		#else
		var finalWidth:Int  = GAME_WIDTH;
		var finalHeight:Int = GAME_HEIGHT;
		#end

		#if LUA_ALLOWED
		Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call));
		#end

		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();

		#if ACHIEVEMENTS_ALLOWED
		Achievements.load();
		#end

		#if COPYSTATE_ALLOWED
		var initialState:Class<FlxState> = !CopyState.checkExistingFiles() ? cast CopyState : cast TitleState;
		#else
		var initialState:Class<FlxState> = TitleState;
		#end

		addChild(new FlxGame(
			finalWidth,
			finalHeight,
			initialState,
			#if (flixel < "5.0.0") zoom, #end
			FRAMERATE,
			FRAMERATE,
			SKIP_SPLASH,
			START_FULLSCREEN
		));

		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		fpsVar.visible = ClientPrefs.data.showFPS;

		Lib.current.stage.align     = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

		#if linux
		Lib.current.stage.window.setIcon(Image.fromFile('icon.png'));
		#end

		#if desktop
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
		#end

		#if html5
		FlxG.autoPause     = false;
		FlxG.mouse.visible = false;
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		#if android
		FlxG.android.preventDefaultKeys = [BACK];
		#end

		#if mobile
		LimeSystem.allowScreenTimeout = ClientPrefs.data.screensaver;
		FlxG.scaleMode = new MobileScaleMode();
		#end

		_applyPlatformOptimizations();

		FlxG.signals.gameResized.add(onGameResized);
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	private function onEnterFrame(e:Event):Void
	{
		var elapsed:Float = FlxG.elapsed * 1000;

		_gcTimer       += elapsed;
		_fpsCheckTimer += elapsed;

		if (_gcTimer >= GC_INTERVAL_MS)
		{
			_gcTimer = 0.0;
			_runGarbageCollection();
		}

		if (_fpsCheckTimer >= FPS_CHECK_INTERVAL)
		{
			_fpsCheckTimer = 0.0;
			_checkFpsHealth();
		}
	}

	private function _runGarbageCollection():Void
	{
		if (OpenFlSystem.totalMemory >= GC_MEMORY_THRESHOLD)
		{
			OpenFlSystem.gc();
			#if cpp
			cpp.NativeGc.run(true);
			#end
		}
	}

	private function _checkFpsHealth():Void
	{
		if (fpsVar == null)
			return;

		var threshold:Int = Std.int(FlxG.drawFramerate * FPS_LOW_THRESHOLD);

		if (fpsVar.currentFPS < threshold)
		{
			_lowFpsStrikes++;
			if (_lowFpsStrikes >= 3 && !_optimized)
				_applyDynamicOptimizations();
		}
		else
		{
			if (_lowFpsStrikes > 0)
				_lowFpsStrikes--;
			if (_optimized && _lowFpsStrikes == 0)
				_restoreOptimizations();
		}
	}

	private function _applyPlatformOptimizations():Void
	{
		#if mobile
		FlxG.drawFramerate   = 60;
		FlxG.updateFramerate = 60;
		FlxG.fixedTimestep   = false;
		#end

		#if html5
		FlxG.drawFramerate   = 60;
		FlxG.updateFramerate = 60;
		#end

		#if desktop
		FlxG.fixedTimestep = false;
		_setVSync(ClientPrefs.data.vsync);
		#end
	}

	private function _applyDynamicOptimizations():Void
	{
		_optimized = true;

		FlxG.drawFramerate   = Std.int(FRAMERATE * 0.75);
		FlxG.updateFramerate = FlxG.drawFramerate;

		if (FlxG.cameras != null)
			for (cam in FlxG.cameras.list)
				if (cam != null)
					cam.antialiasing = false;

		OpenFlSystem.gc();
		#if cpp
		cpp.NativeGc.run(true);
		#end
	}

	private function _restoreOptimizations():Void
	{
		_optimized     = false;
		_lowFpsStrikes = 0;

		FlxG.drawFramerate   = FRAMERATE;
		FlxG.updateFramerate = FRAMERATE;

		var antialiasing:Bool = ClientPrefs.data.antialiasing;
		if (FlxG.cameras != null)
			for (cam in FlxG.cameras.list)
				if (cam != null)
					cam.antialiasing = antialiasing;
	}

	private function _setVSync(enabled:Bool):Void
	{
		#if desktop
		Lib.current.stage.window.vsync = enabled;
		#end
	}

	private function onKeyUp(e:KeyboardEvent):Void
	{
		if (Controls.instance.justReleased('fullscreen'))
			FlxG.fullscreen = !FlxG.fullscreen;
	}

	private function onGameResized(w:Int, h:Int):Void
	{
		if (fpsVar != null)
		{
			var scaleX:Float = Lib.current.stage.stageWidth  / FlxG.width;
			var scaleY:Float = Lib.current.stage.stageHeight / FlxG.height;
			fpsVar.positionFPS(10, 3, Math.min(scaleX, scaleY));
		}

		if (FlxG.cameras != null)
			for (cam in FlxG.cameras.list)
				if (cam != null && cam.filters != null)
					resetSpriteCache(cam.flashSprite);

		if (FlxG.game != null)
			resetSpriteCache(FlxG.game);
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess
		{
			sprite.__cacheBitmap     = null;
			sprite.__cacheBitmapData = null;
		}
	}
}