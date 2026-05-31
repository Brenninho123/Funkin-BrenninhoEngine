package backend.system;

import debug.FPSCounter;

import flixel.FlxGame;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
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
	static final GAME_WIDTH:Int    = 1280;
	static final GAME_HEIGHT:Int   = 720;
	static final FRAMERATE:Int     = 60;
	static final SKIP_SPLASH:Bool  = true;
	static final START_FULLSCREEN:Bool = false;

	public static var fpsVar:FPSCounter;

	public static final platform:String = #if mobile "Mobile" #else "Desktop" #end;

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
		var ratioX:Float = stageWidth  / GAME_WIDTH;
		var ratioY:Float = stageHeight / GAME_HEIGHT;
		zoom = Math.min(ratioX, ratioY);
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

		var initialState = #if COPYSTATE_ALLOWED (!CopyState.checkExistingFiles() ? CopyState : TitleState) #else TitleState #end;

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

		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

		#if linux
		Lib.current.stage.window.setIcon(Image.fromFile('icon.png'));
		#end

		#if desktop
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
		#end

		#if html5
		FlxG.autoPause = false;
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

		FlxG.signals.gameResized.add(onGameResized);
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
		{
			for (cam in FlxG.cameras.list)
				if (cam != null && cam.filters != null)
					resetSpriteCache(cam.flashSprite);
		}

		if (FlxG.game != null)
			resetSpriteCache(FlxG.game);
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess
		{
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}
}
