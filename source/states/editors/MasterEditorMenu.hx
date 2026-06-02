package states.editors;

import backend.WeekData;
import objects.Character;
import states.MainMenuState;
import states.FreeplayState;

class MasterEditorMenu extends MusicBeatState
{
	static final OPTIONS:Array<String> = [
		'Chart Editor',
		'Character Editor',
		'Stage Editor',
		'Week Editor',
		'Menu Character Editor',
		'Dialogue Editor',
		'Dialogue Portrait Editor',
		'Note Splash Debug'
	];

	private var grpTexts:FlxTypedGroup<Alphabet>;
	private var directories:Array<String> = [null];
	private var curSelected:Int  = 0;
	private var curDirectory:Int = 0;
	private var directoryTxt:FlxText;

	override function create():Void
	{
		FlxG.camera.bgColor = FlxColor.BLACK;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Editors Main Menu', null);
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF353535;
		add(bg);

		grpTexts = new FlxTypedGroup<Alphabet>();
		add(grpTexts);

		for (i in 0...OPTIONS.length)
		{
			var leText:Alphabet = new Alphabet(90, 320, OPTIONS[i], true);
			leText.isMenuItem = true;
			leText.targetY    = i;
			leText.snapToPosition();
			grpTexts.add(leText);
		}

		#if MODS_ALLOWED
		var textBG:FlxSprite = new FlxSprite(0, FlxG.height - 42).makeGraphic(FlxG.width, 42, 0xFF000000);
		textBG.alpha = 0.6;
		add(textBG);

		directoryTxt = new FlxText(textBG.x, textBG.y + 4, FlxG.width, '', 32);
		directoryTxt.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER);
		directoryTxt.scrollFactor.set();
		add(directoryTxt);

		for (folder in Mods.getModDirectories())
			directories.push(folder);

		var found:Int = directories.indexOf(Mods.currentModDirectory);
		if (found > -1)
			curDirectory = found;

		changeDirectory();
		#end

		changeSelection();
		FlxG.mouse.visible = false;

		#if mobile
		#if MODS_ALLOWED
		addTouchPad('LEFT_FULL', 'A_B');
		#else
		addTouchPad('UP_DOWN', 'A_B');
		#end
		#end

		super.create();
	}

	override function update(elapsed:Float):Void
	{
		if (controls.UI_UP_P)   changeSelection(-1);
		if (controls.UI_DOWN_P) changeSelection(1);

		#if MODS_ALLOWED
		if (controls.UI_LEFT_P)  changeDirectory(-1);
		if (controls.UI_RIGHT_P) changeDirectory(1);
		#end

		if (controls.BACK)
			MusicBeatState.switchState(new MainMenuState());

		if (controls.ACCEPT)
		{
			FlxG.sound.music.volume = 0;
			FreeplayState.destroyFreeplayVocals();

			switch (OPTIONS[curSelected])
			{
				case 'Chart Editor':
					LoadingState.loadAndSwitchState(new ChartingState(), false);
				case 'Character Editor':
					LoadingState.loadAndSwitchState(new CharacterEditorState(Character.DEFAULT_CHARACTER, false));
				case 'Stage Editor':
					MusicBeatState.switchState(new StageEditorState());
				case 'Week Editor':
					MusicBeatState.switchState(new WeekEditorState());
				case 'Menu Character Editor':
					MusicBeatState.switchState(new MenuCharacterEditorState());
				case 'Dialogue Editor':
					LoadingState.loadAndSwitchState(new DialogueEditorState(), false);
				case 'Dialogue Portrait Editor':
					LoadingState.loadAndSwitchState(new DialogueCharacterEditorState(), false);
				case 'Note Splash Debug':
					MusicBeatState.switchState(new NoteSplashDebugState());
			}
		}

		var index:Int = 0;
		for (item in grpTexts.members)
		{
			item.targetY = index - curSelected;
			item.alpha   = (item.targetY == 0) ? 1.0 : 0.6;
			index++;
		}

		super.update(elapsed);
	}

	function changeSelection(change:Int = 0):Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		curSelected = FlxMath.wrap(curSelected + change, 0, OPTIONS.length - 1);
	}

	#if MODS_ALLOWED
	function changeDirectory(change:Int = 0):Void
	{
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		curDirectory = FlxMath.wrap(curDirectory + change, 0, directories.length - 1);

		WeekData.setDirectoryFromWeek();

		var dir:String = directories[curDirectory];
		if (dir == null || dir.length < 1)
			directoryTxt.text = '< NO MOD DIRECTORY LOADED >';
		else
		{
			Mods.currentModDirectory = dir;
			directoryTxt.text = '< LOADED MOD DIRECTORY: ${dir.toUpperCase()} >';
		}
	}
	#end
}