package states.editors;

import flixel.group.FlxGroup;
import flixel.addons.transition.FlxTransitionableState;
import objects.Character;

class StageEditorState extends MusicBeatState
{
	static final GRID_SIZE:Int       = 50;
	static final SCROLL_SPEED:Float  = 300;
	static final ZOOM_MIN:Float      = 0.3;
	static final ZOOM_MAX:Float      = 2.0;
	static final ZOOM_STEP:Float     = 0.1;

	var stageGroup:FlxTypedGroup<FlxSprite>;
	var uiGroup:FlxGroup;

	var camGame:FlxCamera;
	var camUI:FlxCamera;

	var gridOverlay:FlxSprite;
	var selectedSprite:FlxSprite = null;

	var stageNameTxt:FlxText;
	var helpTxt:FlxText;
	var infoTxt:FlxText;
	var zoomTxt:FlxText;

	var stageName:String  = 'stage';
	var stageZoom:Float   = 0.9;
	var camZoom:Float     = 1.0;
	var showGrid:Bool     = true;
	var isDragging:Bool   = false;
	var dragOffsetX:Float = 0;
	var dragOffsetY:Float = 0;

	var stageSprites:Array<StageObject> = [];
	var curObject:Int = -1;

	var _ready:Bool = false;

	override function create():Void
	{
		camGame           = new FlxCamera();
		camUI             = new FlxCamera();
		camUI.bgColor     = FlxColor.TRANSPARENT;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camUI, false);

		transIn  = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width * 2, FlxG.height * 2, 0xFF1A1A2E);
		bg.screenCenter();
		bg.cameras = [camGame];
		add(bg);

		stageGroup         = new FlxTypedGroup<FlxSprite>();
		stageGroup.cameras = [camGame];
		add(stageGroup);

		gridOverlay         = new FlxSprite().makeGraphic(FlxG.width * 2, FlxG.height * 2, FlxColor.TRANSPARENT);
		gridOverlay.cameras = [camGame];
		gridOverlay.alpha   = 0.15;
		add(gridOverlay);
		_drawGrid();

		uiGroup         = new FlxGroup();
		uiGroup.cameras = [camUI];
		add(uiGroup);

		_buildUI();

		FlxG.mouse.visible = true;
		camGame.zoom       = camZoom;

		#if mobile
		addTouchPad('LEFT_FULL', 'A_B');
		#end

		_ready = true;

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		if (!_ready) return;

		_handleCamera(elapsed);
		_handleKeyboard();
		_handleMouse();
		_handleTouch(elapsed);
		_updateInfo();

		super.update(elapsed);
	}

	private function _handleCamera(elapsed:Float):Void
	{
		var speed:Float = SCROLL_SPEED * elapsed;
		if (FlxG.keys.pressed.SHIFT) speed *= 2.5;

		#if !mobile
		if (FlxG.keys.pressed.W)    camGame.scroll.y -= speed;
		if (FlxG.keys.pressed.S)    camGame.scroll.y += speed;
		if (FlxG.keys.pressed.A)    camGame.scroll.x -= speed;
		if (FlxG.keys.pressed.D)    camGame.scroll.x += speed;
		if (FlxG.keys.justPressed.Q) _setZoom(camZoom - ZOOM_STEP);
		if (FlxG.keys.justPressed.E) _setZoom(camZoom + ZOOM_STEP);
		if (FlxG.keys.justPressed.R) { camGame.scroll.set(0, 0); _setZoom(1.0); }
		#end
	}

	private function _handleMouse():Void
	{
		#if !mobile
		if (camGame == null) return;

		var worldPos = FlxG.mouse.getWorldPosition(camGame);
		if (worldPos == null) return;

		if (FlxG.mouse.justPressed)
		{
			selectedSprite = null;
			curObject      = -1;

			for (i in 0...stageSprites.length)
			{
				var obj:StageObject = stageSprites[i];
				if (obj.sprite != null && FlxG.mouse.overlaps(obj.sprite, camGame))
				{
					selectedSprite = obj.sprite;
					curObject      = i;
					isDragging     = true;
					dragOffsetX    = obj.sprite.x - worldPos.x;
					dragOffsetY    = obj.sprite.y - worldPos.y;
					break;
				}
			}
		}

		if (FlxG.mouse.pressed && isDragging && selectedSprite != null)
		{
			var wx:Float = worldPos.x;
			var wy:Float = worldPos.y;

			selectedSprite.x = wx + dragOffsetX;
			selectedSprite.y = wy + dragOffsetY;

			if (FlxG.keys.pressed.CONTROL)
			{
				selectedSprite.x = Math.round(selectedSprite.x / GRID_SIZE) * GRID_SIZE;
				selectedSprite.y = Math.round(selectedSprite.y / GRID_SIZE) * GRID_SIZE;
			}

			if (curObject >= 0 && curObject < stageSprites.length)
			{
				stageSprites[curObject].x = Std.int(selectedSprite.x);
				stageSprites[curObject].y = Std.int(selectedSprite.y);
			}
		}

		if (FlxG.mouse.justReleased) isDragging = false;

		if (FlxG.mouse.wheel != 0)
			_setZoom(camZoom + FlxG.mouse.wheel * ZOOM_STEP * 0.5);
		#end
	}

	private function _handleKeyboard():Void
	{
		#if !mobile
		if (FlxG.keys.justPressed.ESCAPE)
		{
			_exit();
			return;
		}

		if (FlxG.keys.justPressed.G)
		{
			showGrid            = !showGrid;
			gridOverlay.visible = showGrid;
		}

		if (FlxG.keys.justPressed.F1)  helpTxt.visible = !helpTxt.visible;
		if (FlxG.keys.justPressed.F5)  _saveStage();
		if (FlxG.keys.justPressed.F6)  _loadStage();

		if (selectedSprite != null)
		{
			var step:Float = FlxG.keys.pressed.SHIFT ? 10 : 1;
			if (FlxG.keys.justPressed.LEFT)  { selectedSprite.x -= step; _syncObjectPos(); }
			if (FlxG.keys.justPressed.RIGHT) { selectedSprite.x += step; _syncObjectPos(); }
			if (FlxG.keys.justPressed.UP)    { selectedSprite.y -= step; _syncObjectPos(); }
			if (FlxG.keys.justPressed.DOWN)  { selectedSprite.y += step; _syncObjectPos(); }
			if (FlxG.keys.justPressed.DELETE && curObject >= 0) _removeObject(curObject);
		}
		#end
	}

	private function _handleTouch(elapsed:Float):Void
	{
		#if mobile
		if (touchPad == null) return;

		var speed:Float = SCROLL_SPEED * elapsed;

		if (touchPad.buttonLeft.pressed)        camGame.scroll.x -= speed;
		if (touchPad.buttonRight.pressed)       camGame.scroll.x += speed;
		if (touchPad.buttonUp.pressed)          camGame.scroll.y -= speed;
		if (touchPad.buttonDown.pressed)        camGame.scroll.y += speed;
		if (touchPad.buttonLeft2.justPressed)   _setZoom(camZoom - ZOOM_STEP);
		if (touchPad.buttonRight2.justPressed)  _setZoom(camZoom + ZOOM_STEP);
		if (touchPad.buttonUp2.justPressed)     { showGrid = !showGrid; gridOverlay.visible = showGrid; }
		if (touchPad.buttonDown2.justPressed)   { camGame.scroll.set(0, 0); _setZoom(1.0); }
		if (touchPad.buttonA.justPressed && selectedSprite != null && curObject >= 0) _removeObject(curObject);
		if (touchPad.buttonB.justPressed) { _exit(); return; }
		#end
	}

	private function _syncObjectPos():Void
	{
		if (selectedSprite == null || curObject < 0 || curObject >= stageSprites.length) return;
		stageSprites[curObject].x = Std.int(selectedSprite.x);
		stageSprites[curObject].y = Std.int(selectedSprite.y);
	}

	private function _buildUI():Void
	{
		var topBar:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 36, 0xDD000000);
		topBar.cameras = [camUI];
		uiGroup.add(topBar);

		stageNameTxt = new FlxText(10, 8, 0, 'Stage Editor — $stageName', 16);
		stageNameTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, LEFT);
		stageNameTxt.cameras = [camUI];
		uiGroup.add(stageNameTxt);

		zoomTxt = new FlxText(FlxG.width - 120, 8, 110, 'Zoom: 100%', 14);
		zoomTxt.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, RIGHT);
		zoomTxt.cameras = [camUI];
		uiGroup.add(zoomTxt);

		#if !mobile
		helpTxt = new FlxText(10, FlxG.height - 26, FlxG.width - 20,
			'[WASD] Scroll  [Q/E] Zoom  [R] Reset  [G] Grid  [CTRL] Snap  [Arrows] Nudge  [DEL] Delete  [F5] Save  [F6] Load  [ESC] Back',
			10);
		#else
		helpTxt = new FlxText(10, FlxG.height - 26, FlxG.width - 20,
			'[D-Pad] Scroll  [L2/R2] Zoom  [UP2] Grid  [DOWN2] Reset  [A] Delete  [B] Back',
			10);
		#end
		helpTxt.setFormat(Paths.font('vcr.ttf'), 10, 0xFFCCCCCC, CENTER);
		helpTxt.cameras = [camUI];
		uiGroup.add(helpTxt);

		infoTxt = new FlxText(10, 44, 0, '', 12);
		infoTxt.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, LEFT);
		infoTxt.cameras = [camUI];
		uiGroup.add(infoTxt);
	}

	private function _updateInfo():Void
	{
		if (camGame == null || infoTxt == null || zoomTxt == null || stageNameTxt == null) return;

		var mx:Float = 0;
		var my:Float = 0;

		#if !mobile
		try
		{
			var wp = FlxG.mouse.getWorldPosition(camGame);
			if (wp != null) { mx = wp.x; my = wp.y; }
		}
		catch (e:Dynamic) {}
		#end

		var info:String = 'Mouse: (${Std.int(mx)}, ${Std.int(my)})  Objects: ${stageSprites.length}';

		if (selectedSprite != null && curObject >= 0 && curObject < stageSprites.length)
		{
			var obj:StageObject = stageSprites[curObject];
			info += '  Selected: ${obj.name} (${Std.int(selectedSprite.x)}, ${Std.int(selectedSprite.y)})';
		}

		infoTxt.text      = info;
		zoomTxt.text      = 'Zoom: ${Math.round(camZoom * 100)}%';
		stageNameTxt.text = 'Stage Editor — $stageName';
	}

	private function _setZoom(value:Float):Void
	{
		camZoom      = FlxMath.bound(value, ZOOM_MIN, ZOOM_MAX);
		camGame.zoom = camZoom;
	}

	private function _drawGrid():Void
	{
		var bmd       = new openfl.display.BitmapData(FlxG.width * 2, FlxG.height * 2, true, FlxColor.TRANSPARENT);
		var lineColor = 0x33FFFFFF;

		var x:Int = 0;
		while (x < FlxG.width * 2)
		{
			for (py in 0...FlxG.height * 2) bmd.setPixel32(x, py, lineColor);
			x += GRID_SIZE;
		}

		var y:Int = 0;
		while (y < FlxG.height * 2)
		{
			for (px in 0...FlxG.width * 2) bmd.setPixel32(px, y, lineColor);
			y += GRID_SIZE;
		}

		gridOverlay.pixels = bmd;
	}

	private function _exit():Void
	{
		FlxG.mouse.visible = false;
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	private function _removeObject(index:Int):Void
	{
		if (index < 0 || index >= stageSprites.length) return;
		var obj:StageObject = stageSprites[index];
		if (obj.sprite != null) stageGroup.remove(obj.sprite, true);
		stageSprites.splice(index, 1);
		selectedSprite = null;
		curObject      = -1;
	}

	private function _saveStage():Void
	{
		var objects:Array<Dynamic> = stageSprites.map((o:StageObject) -> {
			name:    o.name,
			image:   o.image,
			x:       o.x,
			y:       o.y,
			scrollX: o.scrollX,
			scrollY: o.scrollY,
			scaleX:  o.scaleX,
			scaleY:  o.scaleY,
			alpha:   o.alpha,
			layer:   o.layer
		});

		var data:Dynamic = {
			name:        stageName,
			zoom:        stageZoom,
			cameraSpeed: 1.0,
			objects:     objects
		};

		try
		{
			var path:String = Paths.getSharedPath('stages/$stageName.json');
			#if MODS_ALLOWED
			path = Paths.modFolders('stages/$stageName.json');
			#end
			sys.io.File.saveContent(path, haxe.Json.stringify(data, null, '\t'));
			CoolUtil.showPopUp('Stage "$stageName" saved!', 'Success');
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp('Failed to save: $e', 'Error');
		}
	}

	private function _loadStage():Void
	{
		try
		{
			var path:String = Paths.getSharedPath('stages/$stageName.json');
			#if MODS_ALLOWED
			var modPath:String = Paths.modFolders('stages/$stageName.json');
			if (sys.FileSystem.exists(modPath)) path = modPath;
			#end

			if (!sys.FileSystem.exists(path))
			{
				CoolUtil.showPopUp('Stage not found: $stageName', 'Error');
				return;
			}

			var data:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));

			for (obj in stageSprites)
				if (obj.sprite != null) stageGroup.remove(obj.sprite, true);
			stageSprites   = [];
			selectedSprite = null;
			curObject      = -1;

			stageZoom = Reflect.field(data, 'zoom') ?? 0.9;

			var objects:Array<Dynamic> = Reflect.field(data, 'objects') ?? [];
			for (o in objects)
			{
				var sObj:StageObject = {
					name:    Reflect.field(o, 'name')    ?? 'object',
					image:   Reflect.field(o, 'image')   ?? '',
					x:       Reflect.field(o, 'x')       ?? 0,
					y:       Reflect.field(o, 'y')       ?? 0,
					scrollX: Reflect.field(o, 'scrollX') ?? 1.0,
					scrollY: Reflect.field(o, 'scrollY') ?? 1.0,
					scaleX:  Reflect.field(o, 'scaleX')  ?? 1.0,
					scaleY:  Reflect.field(o, 'scaleY')  ?? 1.0,
					alpha:   Reflect.field(o, 'alpha')   ?? 1.0,
					layer:   Reflect.field(o, 'layer')   ?? 0,
					sprite:  null
				};

				if (sObj.image.length > 0)
				{
					var spr:FlxSprite = new FlxSprite(sObj.x, sObj.y);
					spr.loadGraphic(Paths.image(sObj.image));
					spr.scrollFactor.set(sObj.scrollX, sObj.scrollY);
					spr.scale.set(sObj.scaleX, sObj.scaleY);
					spr.alpha        = sObj.alpha;
					spr.antialiasing = ClientPrefs.data.antialiasing;
					sObj.sprite      = spr;
					stageGroup.add(spr);
				}

				stageSprites.push(sObj);
			}

			CoolUtil.showPopUp('Loaded "$stageName" (${stageSprites.length} objects)', 'Success');
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp('Failed to load: $e', 'Error');
		}
	}
}

typedef StageObject =
{
	var name:String;
	var image:String;
	var x:Int;
	var y:Int;
	var scrollX:Float;
	var scrollY:Float;
	var scaleX:Float;
	var scaleY:Float;
	var alpha:Float;
	var layer:Int;
	var ?sprite:FlxSprite;
}