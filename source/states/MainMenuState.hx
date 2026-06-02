package states;

import flixel.FlxObject;
import flixel.addons.transition.FlxTransitionableState;
import flixel.effects.FlxFlicker;
import lime.app.Application;
import states.editors.MasterEditorMenu;
import options.OptionsState;
import online.users.OnlineUsers;
import audio.Audio;

class MainMenuState extends MusicBeatState
{
	public static var psychEngineVersion:String = '0.1.1';
	public static var curSelected:Int = 0;

	static final OPTIONS:Array<String> = [
		'story_mode',
		'freeplay',
		#if MODS_ALLOWED
		'mods',
		#end
		'credits',
		'options'
	];

	var menuItems:FlxTypedGroup<FlxSprite>;
	var magenta:FlxSprite;
	var camFollow:FlxObject;

	var onlineCountBg:FlxSprite;
	var onlineCountTxt:FlxText;
	var onlineDot:FlxSprite;

	var versionTxt:FlxText;
	var fnfVerTxt:FlxText;

	var selectedSomethin:Bool = false;
	var _dotPulseTimer:Float  = 0.0;

	override function create():Void
	{
		#if MODS_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('In the Menus', null);
		#end

		transIn  = FlxTransitionableState.defaultTransIn;
		transOut = FlxTransitionableState.defaultTransOut;

		persistentUpdate = persistentDraw = true;

		var yScroll:Float = Math.max(0.25 - (0.05 * (OPTIONS.length - 4)), 0.1);

		var bg:FlxSprite = new FlxSprite(-80).loadGraphic(Paths.image('menuBG'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set(0, yScroll);
		bg.setGraphicSize(Std.int(bg.width * 1.175));
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);

		magenta = new FlxSprite(-80).loadGraphic(Paths.image('menuDesat'));
		magenta.antialiasing = ClientPrefs.data.antialiasing;
		magenta.scrollFactor.set(0, yScroll);
		magenta.setGraphicSize(Std.int(magenta.width * 1.175));
		magenta.updateHitbox();
		magenta.screenCenter();
		magenta.visible = false;
		magenta.color   = 0xFFfd719b;
		add(magenta);

		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		for (i in 0...OPTIONS.length)
		{
			var offset:Float       = 108 - (Math.max(OPTIONS.length, 4) - 4) * 80;
			var menuItem:FlxSprite = new FlxSprite(0, (i * 140) + offset);
			menuItem.antialiasing  = ClientPrefs.data.antialiasing;
			menuItem.frames        = Paths.getSparrowAtlas('mainmenu/menu_' + OPTIONS[i]);
			menuItem.animation.addByPrefix('idle',     OPTIONS[i] + ' basic', 24);
			menuItem.animation.addByPrefix('selected', OPTIONS[i] + ' white', 24);
			menuItem.animation.play('idle');
			var scr:Float = OPTIONS.length < 6 ? 0 : (OPTIONS.length - 4) * 0.135;
			menuItem.scrollFactor.set(0, scr);
			menuItem.updateHitbox();
			menuItem.screenCenter(X);
			menuItems.add(menuItem);
		}

		_buildOnlineCounter();
		_buildVersionTexts();

		changeItem();

		#if ACHIEVEMENTS_ALLOWED
		var leDate = Date.now();
		if (leDate.getDay() == 5 && leDate.getHours() >= 18)
			Achievements.unlock('friday_night_play');
		#if MODS_ALLOWED
		Achievements.reloadList();
		#end
		#end

		#if mobile
		addTouchPad('UP_DOWN', 'A_B_E');
		#end

		OnlineUsers.onUsersUpdated = function(_):Void { _updateOnlineCounter(); };
		OnlineUsers.fetchUsers(function(_) _updateOnlineCounter(), null);

		super.create();
		FlxG.camera.follow(camFollow, null, 9);
	}

	private function _buildOnlineCounter():Void
	{
		onlineCountBg = new FlxSprite(FlxG.width - 200, 8).makeGraphic(192, 38, 0xBB000000);
		onlineCountBg.scrollFactor.set();
		add(onlineCountBg);

		onlineDot = new FlxSprite(FlxG.width - 188, 23).makeGraphic(8, 8, 0xFF44FF44);
		onlineDot.scrollFactor.set();
		add(onlineDot);

		onlineCountTxt = new FlxText(FlxG.width - 178, 15, 166, '0 online', 13);
		onlineCountTxt.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.WHITE, RIGHT);
		onlineCountTxt.scrollFactor.set();
		add(onlineCountTxt);
	}

	private function _buildVersionTexts():Void
	{
		versionTxt = new FlxText(12, FlxG.height - 44, 0, 'Brenninho Engine v' + psychEngineVersion, 12);
		versionTxt.scrollFactor.set();
		versionTxt.setFormat('VCR OSD Mono', 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(versionTxt);

		fnfVerTxt = new FlxText(12, FlxG.height - 24, 0, "Friday Night Funkin' v" + Application.current.meta.get('version'), 12);
		fnfVerTxt.scrollFactor.set();
		fnfVerTxt.setFormat('VCR OSD Mono', 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(fnfVerTxt);
	}

	private function _updateOnlineCounter():Void
	{
		var count:Int      = OnlineUsers.getUserCount();
		var quality:String = online.Online.getConnectionQuality();

		var dotColor:Int = switch (quality) {
			case 'Excellent': 0xFF44FF44;
			case 'Good':      0xFF88FF44;
			case 'Fair':      0xFFFFCC00;
			case 'Poor':      0xFFFF6600;
			default:          0xFFFF3333;
		};

		onlineDot.color      = dotColor;
		onlineCountTxt.text  = '$count online';
		onlineCountTxt.color = count > 0 ? FlxColor.WHITE : 0xFF888888;
	}

	private function _handleAccept():Void
	{
		FlxG.sound.play(Paths.sound('confirmMenu'));

		if (OPTIONS[curSelected] == 'donate')
		{
			CoolUtil.browserLoad('https://ninja-muffin24.itch.io/funkin');
			return;
		}

		selectedSomethin = true;

		if (ClientPrefs.data.flashing)
			FlxFlicker.flicker(magenta, 1.1, 0.15, false);

		FlxFlicker.flicker(menuItems.members[curSelected], 1, 0.06, false, false, function(_:FlxFlicker):Void
		{
			switch (OPTIONS[curSelected])
			{
				case 'story_mode': MusicBeatState.switchState(new StoryMenuState());
				case 'freeplay':   MusicBeatState.switchState(new FreeplayState());
				#if MODS_ALLOWED
				case 'mods':       MusicBeatState.switchState(new ModsMenuState());
				#end
				case 'credits':    MusicBeatState.switchState(new CreditsState());
				case 'options':
					MusicBeatState.switchState(new OptionsState());
					OptionsState.onPlayState = false;
					if (PlayState.SONG != null)
					{
						PlayState.SONG.arrowSkin  = null;
						PlayState.SONG.splashSkin = null;
						PlayState.stageUI = 'normal';
					}
			}
		});

		for (i in 0...menuItems.members.length)
		{
			if (i == curSelected) continue;
			FlxTween.tween(menuItems.members[i], {alpha: 0}, 0.4, {
				ease: FlxEase.quadOut,
				onComplete: function(_:FlxTween):Void { menuItems.members[i].kill(); }
			});
		}
	}

	override function update(elapsed:Float):Void
	{
		if (FlxG.sound.music.volume < 0.8)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
			if (FreeplayState.vocals != null)
				FreeplayState.vocals.volume += 0.5 * elapsed;
		}

		_dotPulseTimer += elapsed;
		if (_dotPulseTimer >= 3.0)
		{
			_dotPulseTimer = 0.0;
			_updateOnlineCounter();
		}

		OnlineUsers.update(elapsed);

		if (!selectedSomethin)
		{
			if (controls.UI_UP_P)   changeItem(-1);
			if (controls.UI_DOWN_P) changeItem(1);

			if (controls.BACK)
			{
				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new TitleState());
			}

			if (controls.ACCEPT)
				_handleAccept();

			#if mobile
			if (controls.justPressed('debug_1') || touchPad.buttonE.justPressed)
			#else
			if (controls.justPressed('debug_1'))
			#end
			{
				selectedSomethin = true;
				MusicBeatState.switchState(new MasterEditorMenu());
			}
		}

		super.update(elapsed);
	}

	function changeItem(huh:Int = 0):Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'));
		menuItems.members[curSelected].animation.play('idle');
		menuItems.members[curSelected].updateHitbox();
		menuItems.members[curSelected].screenCenter(X);

		curSelected = FlxMath.wrap(curSelected + huh, 0, OPTIONS.length - 1);

		menuItems.members[curSelected].animation.play('selected');
		menuItems.members[curSelected].centerOffsets();
		menuItems.members[curSelected].screenCenter(X);

		camFollow.setPosition(
			menuItems.members[curSelected].getGraphicMidpoint().x,
			menuItems.members[curSelected].getGraphicMidpoint().y - (OPTIONS.length > 4 ? OPTIONS.length * 8 : 0)
		);
	}
}