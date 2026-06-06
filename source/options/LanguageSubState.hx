package options;

import language.Language;

class LanguageSubState extends MusicBeatSubstate
{
	private var _grp:FlxTypedGroup<Alphabet>;
	private var _flags:Array<FlxText>     = [];
	private var _curSelected:Int          = 0;
	private var _selectorLeft:Alphabet;
	private var _selectorRight:Alphabet;
	private var _bg:FlxSprite;
	private var _title:FlxText;
	private var _hint:FlxText;

	override function create():Void
	{
		super.create();

		_bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
		_bg.alpha = 0;
		add(_bg);
		FlxTween.tween(_bg, {alpha: 0.7}, 0.3, {ease: FlxEase.quartOut});

		_title = new FlxText(0, 20, FlxG.width, Language.get('options.language'), 32);
		_title.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_title.borderSize   = 2;
		_title.scrollFactor.set();
		_title.alpha = 0;
		add(_title);
		FlxTween.tween(_title, {alpha: 1}, 0.3, {ease: FlxEase.quartOut, startDelay: 0.1});

		_grp = new FlxTypedGroup<Alphabet>();
		add(_grp);

		var available = Language.available;
		for (i in 0...available.length)
		{
			var info    = available[i];
			var label   = '${info.nativeName}  (${info.name})';

			var text:Alphabet = new Alphabet(0, 0, label, true);
			text.screenCenter();
			text.y     += (100 * (i - (available.length / 2))) + 50;
			text.alpha  = 0;
			_grp.add(text);

			var flag:FlxText = new FlxText(text.x - 60, text.y + 8, 0, info.flag, 28);
			flag.alpha = 0;
			add(flag);
			_flags.push(flag);

			FlxTween.tween(text, {alpha: 0.6}, 0.25, {ease: FlxEase.quartOut, startDelay: 0.1 + i * 0.05});
			FlxTween.tween(flag, {alpha: 0.6}, 0.25, {ease: FlxEase.quartOut, startDelay: 0.1 + i * 0.05});
		}

		_selectorLeft  = new Alphabet(0, 0, '>', true);
		_selectorRight = new Alphabet(0, 0, '<', true);
		add(_selectorLeft);
		add(_selectorRight);

		_hint = new FlxText(0, FlxG.height - 30, FlxG.width,
			#if mobile '[A] Select    [B] Back' #else '[ENTER] Select    [ESCAPE] Back' #end, 16);
		_hint.setFormat(Paths.font('vcr.ttf'), 16, 0xFFCCCCCC, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_hint.borderSize   = 1;
		_hint.scrollFactor.set();
		add(_hint);

		var curCode:String = Language.getCurrentCode();
		for (i in 0...available.length)
			if (available[i].code == curCode) { _curSelected = i; break; }

		_changeSelection();

		#if mobile
		addTouchPad('UP_DOWN', 'A_B');
		#end
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (controls.UI_UP_P)   _changeSelection(-1);
		if (controls.UI_DOWN_P) _changeSelection(1);

		if (controls.ACCEPT)
		{
			var selected = Language.available[_curSelected];
			Language.set(selected.code);
			FlxG.sound.play(Paths.sound('confirmMenu'));

			FlxTween.tween(_bg, {alpha: 0}, 0.25, {ease: FlxEase.quartIn,
				onComplete: function(_:FlxTween):Void { close(); }
			});
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			FlxTween.tween(_bg, {alpha: 0}, 0.25, {ease: FlxEase.quartIn,
				onComplete: function(_:FlxTween):Void { close(); }
			});
		}
	}

	private function _changeSelection(change:Int = 0):Void
	{
		_curSelected += change;
		if (_curSelected < 0)                        _curSelected = Language.available.length - 1;
		if (_curSelected >= Language.available.length) _curSelected = 0;

		for (i in 0..._grp.members.length)
		{
			var item:Alphabet  = _grp.members[i];
			var flag:FlxText   = _flags[i];
			item.targetY       = i - _curSelected;
			var selected:Bool  = item.targetY == 0;

			item.alpha = selected ? 1.0 : 0.6;
			flag.alpha = selected ? 1.0 : 0.6;

			if (selected)
			{
				_selectorLeft.x  = item.x - 63;
				_selectorLeft.y  = item.y;
				_selectorRight.x = item.x + item.width + 15;
				_selectorRight.y = item.y;

				flag.x = item.x - 60;
				flag.y = item.y + 8;
			}
		}

		if (change != 0) FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	override function destroy():Void
	{
		#if mobile
		removeTouchPad();
		#end
		super.destroy();
	}
}
