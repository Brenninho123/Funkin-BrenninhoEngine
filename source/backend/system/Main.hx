package backend.system;

import debug.FPSCounter;
import api.APISystem;
import api.APIHelper;
import audio.Audio;
import online.Online;
import online.users.OnlineUsers;

import flixel.FlxGame;
import flixel.FlxState;
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

	static final GC_MEMORY_THRESHOLD:Float     = 800 * 1024 * 1024;
	static final GC_INTERVAL_MS:Float          = 30000;
	static final FPS_LOW_THRESHOLD:Float       = 0.5;
	static final FPS_CHECK_INTERVAL:Float      = 5000;
	static final SYSTEMS_UPDATE_INTERVAL:Float = 2000;

	public static var fpsVar:FPSCounter;
	public static final platform:String = #if mobile "Mobile" #else "Desktop" #end;

	private var _gcTimer:Float           = 0.0;
	private var _fpsCheckTimer:Float     = 0.0;
	private var _systemsTimer:Float      = 0.0;
	private var _lowFpsStrikes:Int       = 0;
	private var _optimized:Bool          = false;
	private var _paused:Bool             = false;
	private var _startTime:Float         = 0.0;
	private var _frameCount:Int          = 0;
	private var _setupDone:Bool          = false;

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

		_startTime = Date.now().getTime();

		#if android
		try { StorageUtil.requestPermissions(); } catch (e:Dynamic) {}
		#end

		#if mobile
		try { Sys.setCwd(StorageUtil.getStorageDirectory()); } catch (e:Dynamic) {}
		#end

		try { backend.CrashHandler.init(); } catch (e:Dynamic) {}

		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	private function init(?e:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		if (_setupDone) return;
		_setupDone = true;

		_initWindowHints();
		_setupGame();
	}

	private function _initWindowHints():Void
	{
		#if windows
		@:functionCode('
			setProcessDPIAware();
			DisableProcessWindowsGhosting();
		')
		#end
	}

	private function _initSystems():Void
	{
		try
		{
			APISystem.init();
			APIHelper.init();

			APIHelper.onThreatDetected = function(threat:String):Void
			{
				FlxG.log.add('[SECURITY] $threat');
			};
		}
		catch (e:Dynamic)
		{
			FlxG.log.add('[WARN] API systems failed to init: $e');
		}

		try
		{
			Online.init();
			Online.onConnectionChanged = function(connected:Bool):Void
			{
				if (connected) OnlineUsers.fetchUsers(null, null);
			};
			OnlineUsers.init();
		}
		catch (e:Dynamic)
		{
			FlxG.log.add('[WARN] Online systems failed to init: $e');
		}

		try
		{
			Audio.init();
			Audio.onVolumeChanged = function(volume:Float):Void {};
		}
		catch (e:Dynamic)
		{
			FlxG.log.add('[WARN] Audio system failed to init: $e');
		}
	}

	private function _setupGame():Void
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
		try
		{
			Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call));
		}
		catch (e:Dynamic) {}
		#end

		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();

		#if ACHIEVEMENTS_ALLOWED
		try { Achievements.load(); } catch (e:Dynamic) {}
		#end

		#if COPYSTATE_ALLOWED
		var initialState:Class<FlxState> = !CopyState.checkExistingFiles() ? cast CopyState : cast TitleState;
		#else
		var initialState:Class<FlxState> = TitleState;
		#end

		var game:FlxGame = new FlxGame(
			finalWidth,
			finalHeight,
			initialState,
			#if (flixel < "5.0.0") zoom, #end
			FRAMERATE,
			FRAMERATE,
			SKIP_SPLASH,
			START_FULLSCREEN
		);

		addChild(game);

		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		fpsVar.visible = ClientPrefs.data.showFPS;

		Lib.current.stage.align     = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

		#if linux
		try { Lib.current.stage.window.setIcon(Image.fromFile('icon.png')); } catch (e:Dynamic) {}
		#end

		#if desktop
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, _onKeyUp);
		#end

		#if html5
		FlxG.autoPause     = false;
		FlxG.mouse.visible = false;
		#end

		#if DISCORD_ALLOWED
		try { DiscordClient.prepare(); } catch (e:Dynamic) {}
		#end

		#if android
		try { FlxG.android.preventDefaultKeys = [BACK]; } catch (e:Dynamic) {}
		#end

		#if mobile
		try
		{
			LimeSystem.allowScreenTimeout = ClientPrefs.data.screensaver;
			FlxG.scaleMode = new MobileScaleMode();
		}
		catch (e:Dynamic) {}
		#end

		_applyPlatformOptimizations();
		_setupWindowEvents();

		FlxG.signals.gameResized.add(_onGameResized);
		addEventListener(Event.ENTER_FRAME, _onEnterFrame);

		_initSystems();
	}

	private function _setupWindowEvents():Void
	{
		#if desktop
		try
		{
			Lib.current.stage.window.onFocusIn.add(function():Void
			{
				_paused = false;
				try { Audio.resumeAll(); } catch (e:Dynamic) {}
			});

			Lib.current.stage.window.onFocusOut.add(function():Void
			{
				_paused = true;
				if (ClientPrefs.data.autoPause)
					try { Audio.pauseAll(); } catch (e:Dynamic) {}
			});

			Lib.current.stage.window.onClose.add(function():Void
			{
				_onShutdown();
			});
		}
		catch (e:Dynamic) {}
		#end
	}

	private function _onShutdown():Void
	{
		try { APIHelper.flushAuditLog(); }   catch (e:Dynamic) {}
		try { Online.clearPendingUploads(); } catch (e:Dynamic) {}
		try { Audio.stopAll(); }              catch (e:Dynamic) {}

		#if DISCORD_ALLOWED
		try
		{
			if (DiscordClient.isInitialized)
				DiscordClient.shutdown();
		}
		catch (e:Dynamic) {}
		#end
	}

	private function _onEnterFrame(e:Event):Void
	{
		_frameCount++;

		if (_paused) return;

		var elapsed:Float   = FlxG.elapsed;
		var elapsedMs:Float = elapsed * 1000;

		_gcTimer       += elapsedMs;
		_fpsCheckTimer += elapsedMs;
		_systemsTimer  += elapsedMs;

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

		if (_systemsTimer >= SYSTEMS_UPDATE_INTERVAL)
		{
			_systemsTimer = 0.0;
			try { Online.update(elapsed); }      catch (e:Dynamic) {}
			try { OnlineUsers.update(elapsed); } catch (e:Dynamic) {}
		}

		try { Audio.update(elapsed); } catch (e:Dynamic) {}
	}

	private function _runGarbageCollection():Void
	{
		try
		{
			if (OpenFlSystem.totalMemory >= GC_MEMORY_THRESHOLD)
			{
				OpenFlSystem.gc();
				#if cpp
				cpp.NativeGc.run(true);
				#end
			}
		}
		catch (e:Dynamic) {}
	}

	private function _checkFpsHealth():Void
	{
		if (fpsVar == null) return;

		var threshold:Int = Std.int(FlxG.drawFramerate * FPS_LOW_THRESHOLD);

		if (fpsVar.currentFPS < threshold)
		{
			_lowFpsStrikes++;
			if (_lowFpsStrikes >= 3 && !_optimized)
				_applyDynamicOptimizations();
		}
		else
		{
			if (_lowFpsStrikes > 0) _lowFpsStrikes--;
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

		_runGarbageCollection();
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
		try { Lib.current.stage.window.vsync = enabled; } catch (e:Dynamic) {}
		#end
	}

	private function _onKeyUp(e:KeyboardEvent):Void
	{
		try
		{
			if (Controls.instance.justReleased('fullscreen'))
				FlxG.fullscreen = !FlxG.fullscreen;
		}
		catch (e:Dynamic) {}
	}

	private function _onGameResized(w:Int, h:Int):Void
	{
		try
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
		catch (e:Dynamic) {}
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		try
		{
			@:privateAccess
			{
				sprite.__cacheBitmap     = null;
				sprite.__cacheBitmapData = null;
			}
		}
		catch (e:Dynamic) {}
	}

	public static function getUptime():Float
	{
		try
		{
			var instance:Main = cast Lib.current.getChildAt(0);
			return Date.now().getTime() - instance._startTime;
		}
		catch (e:Dynamic) { return 0.0; }
	}

	public static function getUptimeFormatted():String
	{
		var ms:Float   = getUptime();
		var secs:Int   = Std.int(ms / 1000) % 60;
		var mins:Int   = Std.int(ms / 60000) % 60;
		var hours:Int  = Std.int(ms / 3600000);
		return '${hours}h ${mins}m ${secs}s';
	}

	public static function getFrameCount():Int
	{
		try
		{
			var instance:Main = cast Lib.current.getChildAt(0);
			return instance._frameCount;
		}
		catch (e:Dynamic) { return 0; }
	}
}