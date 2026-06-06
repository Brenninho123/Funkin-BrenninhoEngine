package states;

import flixel.FlxSubState;
import flixel.effects.FlxFlicker;
import lime.app.Application;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxGradient;

class FlashingState extends MusicBeatState
{
	public static var leftState:Bool = false;

	private var _warnText:FlxText;
	private var _bg:FlxSprite;
	private var _gradientBg:FlxSprite;
	private var _icon:FlxSprite;
	private var _acceptHint:FlxText;
	private var _backHint:FlxText;
	private var _particles:Array<FlxSprite> = [];
	private var _ready:Bool                 = false;
	private var _pulseTimer:Float           = 0.0;
	private var _particleTimer:Float        = 0.0;

	static final PARTICLE_COUNT:Int         = 18;
	static final PULSE_SPEED:Float          = 2.5;

	override function create():Void
	{
		super.create();

		_bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0A0A0A);
		add(_bg);

		_gradientBg = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height,
			[0xFF0A0A0A, 0xFF1A0A0A, 0xFF2A0505, 0xFF0A0A0A], 1, 90);
		_gradientBg.alpha = 0;
		add(_gradientBg);

		for (i in 0...PARTICLE_COUNT)
		{
			var p:FlxSprite = new FlxSprite(
				FlxG.random.float(0, FlxG.width),
				FlxG.random.float(0, FlxG.height)
			).makeGraphic(
				FlxG.random.int(2, 5),
				FlxG.random.int(2, 5),
				FlxG.random.bool(50) ? 0xFFFF3333 : 0xFFFFFFFF
			);
			p.alpha    = FlxG.random.float(0.05, 0.25);
			p.velocity.y = FlxG.random.float(-15, -40);
			p.velocity.x = FlxG.random.float(-8, 8);
			add(p);
			_particles.push(p);
		}

		var warnBg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width - 80, 280, 0xFF000000);
		warnBg.screenCenter();
		warnBg.alpha = 0.6;
		add(warnBg);

		var borderTop:FlxSprite = new FlxSprite(warnBg.x, warnBg.y).makeGraphic(Std.int(warnBg.width), 3, 0xFFFF3333);
		var borderBot:FlxSprite = new FlxSprite(warnBg.x, warnBg.y + warnBg.height - 3).makeGraphic(Std.int(warnBg.width), 3, 0xFFFF3333);
		add(borderTop);
		add(borderBot);

		var warningLabel:FlxText = new FlxText(0, warnBg.y + 12, FlxG.width, '⚠  WARNING  ⚠', 22);
		warningLabel.setFormat(Paths.font('vcr.ttf'), 22, 0xFFFF3333, CENTER);
		add(warningLabel);

		var message:String = #if mobile
			'This mod contains flashing lights\nthat may affect photosensitive players.\n\nPress A to disable flashing effects.\nPress B to continue anyway.'
		#else
			'This mod contains flashing lights\nthat may affect photosensitive players.\n\nPress ENTER to disable flashing effects.\nPress ESCAPE to continue anyway.'
		#end;

		_warnText = new FlxText(0, warnBg.y + 52, FlxG.width, message, 20);
		_warnText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER);
		add(_warnText);

		#if mobile
		_acceptHint = new FlxText(0, warnBg.y + warnBg.height - 48, FlxG.width, '[ A ] DISABLE FLASHING', 14);
		_backHint   = new FlxText(0, warnBg.y + warnBg.height - 28, FlxG.width, '[ B ] IGNORE', 14);
		#else
		_acceptHint = new FlxText(0, warnBg.y + warnBg.height - 48, FlxG.width, '[ ENTER ] DISABLE FLASHING', 14);
		_backHint   = new FlxText(0, warnBg.y + warnBg.height - 28, FlxG.width, '[ ESCAPE ] IGNORE', 14);
		#end
		_acceptHint.setFormat(Paths.font('vcr.ttf'), 14, 0xFFFF8888, CENTER);
		_backHint.setFormat(Paths.font('vcr.ttf'), 14, 0xFF888888, CENTER);
		add(_acceptHint);
		add(_backHint);

		_bg.alpha          = 0;
		_warnText.alpha    = 0;
		warningLabel.alpha = 0;
		warnBg.alpha       = 0;
		borderTop.alpha    = 0;
		borderBot.alpha    = 0;
		_acceptHint.alpha  = 0;
		_backHint.alpha    = 0;
		for (p in _particles) p.alpha = 0;

		FlxTween.tween(_bg,          {alpha: 1},    0.5, {ease: FlxEase.quartOut});
		FlxTween.tween(warnBg,       {alpha: 0.6},  0.7, {ease: FlxEase.quartOut, startDelay: 0.2});
		FlxTween.tween(borderTop,    {alpha: 1},    0.5, {ease: FlxEase.quartOut, startDelay: 0.3});
		FlxTween.tween(borderBot,    {alpha: 1},    0.5, {ease: FlxEase.quartOut, startDelay: 0.3});
		FlxTween.tween(warningLabel, {alpha: 1},    0.6, {ease: FlxEase.quartOut, startDelay: 0.4});
		FlxTween.tween(_warnText,    {alpha: 1},    0.6, {ease: FlxEase.quartOut, startDelay: 0.6});
		FlxTween.tween(_acceptHint,  {alpha: 1},    0.5, {ease: FlxEase.quartOut, startDelay: 0.8});
		FlxTween.tween(_backHint,    {alpha: 1},    0.5, {ease: FlxEase.quartOut, startDelay: 0.9,
			onComplete: function(_:FlxTween):Void { _ready = true; }
		});

		for (i in 0...PARTICLE_COUNT)
		{
			var p:FlxSprite = _particles[i];
			new FlxTimer().start(FlxG.random.float(0.1, 0.8), function(_:FlxTimer):Void
			{
				FlxTween.tween(p, {alpha: FlxG.random.float(0.05, 0.25)}, 0.4, {ease: FlxEase.quartOut});
			});
		}

		FlxTween.tween(_gradientBg, {alpha: 0.4}, 1.5, {ease: FlxEase.quartOut, startDelay: 0.3});

		controls.isInSubstate = false;

		#if mobile
		addTouchPad("NONE", "A_B");
		#end
	}

	override function update(elapsed:Float):Void
	{
		if (_ready && !leftState)
		{
			_pulseTimer += elapsed * PULSE_SPEED;
			var pulse:Float = 0.75 + Math.sin(_pulseTimer) * 0.25;
			_acceptHint.alpha = pulse;

			_particleTimer += elapsed;
			if (_particleTimer >= 0.08)
			{
				_particleTimer = 0.0;
				for (p in _particles)
				{
					if (p.y < -10)
					{
						p.y          = FlxG.height + 5;
						p.x          = FlxG.random.float(0, FlxG.width);
						p.velocity.y = FlxG.random.float(-15, -40);
						p.velocity.x = FlxG.random.float(-8, 8);
					}
				}
			}

			if (controls.ACCEPT || controls.BACK)
			{
				leftState = true;

				FlxTransitionableState.skipNextTransIn  = true;
				FlxTransitionableState.skipNextTransOut = true;

				if (controls.ACCEPT)
				{
					ClientPrefs.data.flashing = false;
					ClientPrefs.saveSettings();
					FlxG.sound.play(Paths.sound('confirmMenu'));

					FlxFlicker.flicker(_warnText, 0.8, 0.08, false, true, function(_:FlxFlicker):Void
					{
						_fadeOutAndSwitch();
					});
				}
				else
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					_fadeOutAndSwitch();
				}
			}
		}

		super.update(elapsed);
	}

	private function _fadeOutAndSwitch():Void
	{
		for (member in members)
			if (member != null)
				FlxTween.tween(member, {alpha: 0}, 0.5, {ease: FlxEase.quartIn});

		new FlxTimer().start(0.6, function(_:FlxTimer):Void
		{
			MusicBeatState.switchState(new TitleState());
		});
	}
}