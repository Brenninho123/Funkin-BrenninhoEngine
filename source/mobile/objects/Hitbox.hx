package mobile.objects;

import openfl.display.BitmapData;
import openfl.display.Shape;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxSignal.FlxTypedSignal;
import openfl.geom.Matrix;

class Hitbox extends MobileInputManager implements IMobileControls
{
	public var buttonLeft:TouchButton  = new TouchButton(0, 0, [MobileInputID.HITBOX_LEFT,  MobileInputID.NOTE_LEFT]);
	public var buttonDown:TouchButton  = new TouchButton(0, 0, [MobileInputID.HITBOX_DOWN,  MobileInputID.NOTE_DOWN]);
	public var buttonUp:TouchButton    = new TouchButton(0, 0, [MobileInputID.HITBOX_UP,    MobileInputID.NOTE_UP]);
	public var buttonRight:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT]);

	public var buttonExtra:TouchButton  = new TouchButton(0, 0, [MobileInputID.EXTRA_1]);
	public var buttonExtra2:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_2]);

	public var instance:MobileInputManager;
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void>   = new FlxTypedSignal<TouchButton->Void>();

	private var storedButtonsIDs:Map<String, Array<MobileInputID>> = new Map();

	public function new(?extraMode:ExtraActions = NONE)
	{
		super();

		for (button in Reflect.fields(this))
		{
			var field = Reflect.field(this, button);
			if (Std.isOfType(field, TouchButton))
				storedButtonsIDs.set(button, Reflect.getProperty(field, 'IDs'));
		}

		var w:Int = Std.int(FlxG.width / 4);
		var h:Int = FlxG.height;

		switch (extraMode)
		{
			case NONE:
				add(buttonLeft  = createHint(0,         0, w, h, 0xFFC24B99));
				add(buttonDown  = createHint(w,         0, w, h, 0xFF00FFFF));
				add(buttonUp    = createHint(w * 2,     0, w, h, 0xFF12FA05));
				add(buttonRight = createHint(w * 3,     0, w, h, 0xFFF9393F));

			case SINGLE:
				add(buttonLeft  = createHint(0,     0, w, h, 0xFFC24B99));
				add(buttonDown  = createHint(w,     0, w, h, 0xFF00FFFF));
				add(buttonUp    = createHint(w * 2, 0, w, h, 0xFF12FA05));
				add(buttonRight = createHint(w * 3, 0, w, h, 0xFFF9393F));
				add(buttonExtra = createHint(0,     0, FlxG.width, h, 0xFF0066FF));

			case DOUBLE:
				add(buttonLeft   = createHint(0,                    0, w,              h, 0xFFC24B99));
				add(buttonDown   = createHint(w,                    0, w,              h, 0xFF00FFFF));
				add(buttonUp     = createHint(w * 2,                0, w,              h, 0xFF12FA05));
				add(buttonRight  = createHint(w * 3,                0, w,              h, 0xFFF9393F));
				add(buttonExtra2 = createHint(Std.int(FlxG.width / 2), 0, Std.int(FlxG.width / 2), h, 0xFFA6FF00));
				add(buttonExtra  = createHint(0,                    0, Std.int(FlxG.width / 2), h, 0xFF0066FF));
		}

		for (button in Reflect.fields(this))
		{
			if (Std.isOfType(Reflect.field(this, button), TouchButton))
				Reflect.setProperty(Reflect.getProperty(this, button), 'IDs', storedButtonsIDs.get(button));
		}

		storedButtonsIDs.clear();
		scrollFactor.set();
		updateTrackedButtons();

		instance = this;
	}

	override function destroy():Void
	{
		super.destroy();
		onButtonUp.destroy();
		onButtonDown.destroy();

		for (fieldName in Reflect.fields(this))
		{
			var field = Reflect.field(this, fieldName);
			if (Std.isOfType(field, TouchButton))
				Reflect.setField(this, fieldName, FlxDestroyUtil.destroy(field));
		}
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:Int = 0xFFFFFF):TouchButton
	{
		var hint:TouchButton      = new TouchButton(X, Y);
		hint.statusAlphas         = [];
		hint.statusIndicatorType  = NONE;
		hint.loadGraphic(createHintGraphic(Width, Height));
		hint.immovable            = true;
		hint.multiTouch           = true;
		hint.solid                = false;
		hint.moves                = false;
		hint.alpha                = 0.00001;
		hint.color                = Color;
		hint.antialiasing         = ClientPrefs.data.antialiasing;
		hint.canChangeLabelAlpha  = false;

		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end

		if (ClientPrefs.data.hitboxType != "Hidden")
		{
			var pressedTween:FlxTween  = null;
			var releasedTween:FlxTween = null;

			hint.onDown.callback = function():Void
			{
				onButtonDown.dispatch(hint);

				if (pressedTween  != null) pressedTween.cancel();
				if (releasedTween != null) releasedTween.cancel();

				pressedTween = FlxTween.tween(hint, {alpha: ClientPrefs.data.controlsAlpha},
					ClientPrefs.data.controlsAlpha / 100,
					{
						ease: FlxEase.circOut,
						onComplete: function(_:FlxTween):Void { pressedTween = null; }
					}
				);
			};

			hint.onUp.callback = hint.onOut.callback = function():Void
			{
				onButtonUp.dispatch(hint);

				if (pressedTween  != null) pressedTween.cancel();
				if (releasedTween != null) releasedTween.cancel();

				releasedTween = FlxTween.tween(hint, {alpha: 0.00001},
					ClientPrefs.data.controlsAlpha / 10,
					{
						ease: FlxEase.circIn,
						onComplete: function(_:FlxTween):Void { releasedTween = null; }
					}
				);
			};
		}
		else
		{
			hint.onDown.callback = function():Void { onButtonDown.dispatch(hint); };
			hint.onUp.callback   = hint.onOut.callback = function():Void { onButtonUp.dispatch(hint); };
		}

		return hint;
	}

	private function createHintGraphic(Width:Int, Height:Int):FlxGraphic
	{
		var shape:Shape = new Shape();

		if (ClientPrefs.data.hitboxType == "No Gradient")
		{
			var matrix:Matrix = new Matrix();
			matrix.createGradientBox(Width, Height, 0, 0, 0);
			shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, 0xFFFFFF], [0, 1], [60, 255], matrix, PAD, RGB, 0);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else if (ClientPrefs.data.hitboxType == "No Gradient (Old)")
		{
			shape.graphics.lineStyle(10, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else
		{
			shape.graphics.lineStyle(3, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.lineStyle(0, 0, 0);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
			shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, FlxColor.TRANSPARENT], [1, 0], [0, 255], null, null, null, 0.5);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
		}

		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0);
		bitmap.draw(shape);
		return FlxG.bitmap.add(bitmap);
	}
}