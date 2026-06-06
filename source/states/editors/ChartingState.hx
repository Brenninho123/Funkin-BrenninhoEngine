package states.editors;

import flash.geom.Rectangle;
import haxe.Json;
import haxe.io.Bytes;
import flixel.FlxObject;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUISlider;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.ui.FlxButton;
import flixel.util.FlxSort;
import flixel.util.FlxGradient;
import lime.media.AudioBuffer;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;
import backend.Song;
import backend.Section;
import backend.StageData;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.HealthIcon;
import objects.AttachedSprite;
import objects.Character;
import substates.Prompt;
import support.vslice.ChartVSlice;

#if sys
import flash.media.Sound;
#end

@:access(flixel.sound.FlxSound._sound)
@:access(openfl.media.Sound.__buffer)

class ChartingState extends MusicBeatState
{
	public static var noteTypeList:Array<String> = [
		'', 'Alt Animation', 'Hey!', 'Hurt Note', 'GF Sing', 'No Animation'
	];

	public var ignoreWarnings:Bool = false;
	var curNoteTypes:Array<String> = [];
	var undos:Array<Dynamic>       = [];
	var redos:Array<Dynamic>       = [];

	var eventStuff:Array<Dynamic> = [
		['', "Nothing. Yep, that's right."],
		['Dadbattle Spotlight', "Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"],
		['Hey!', "Plays the Hey! animation,\nValue 1: BF/GF/Both\nValue 2: Duration (default 0.6s)"],
		['Set GF Speed', "Value 1: 1=Normal, 2=Half speed etc.\nWarning: must be integer!"],
		['Philly Glow', "Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset"],
		['Kill Henchmen', "For Mom's songs."],
		['Add Camera Zoom', "Value 1: Camera zoom (Default: 0.015)\nValue 2: UI zoom (Default: 0.03)"],
		['BG Freaks Expression', "Only in school stage!"],
		['Trigger BG Ghouls', "Only in schoolEvil stage!"],
		['Play Animation', "Value 1: Animation name\nValue 2: Character (Dad, BF, GF)"],
		['Camera Follow Pos', "Value 1: X\nValue 2: Y\nLeave blank to reset."],
		['Alt Idle Animation', "Value 1: Character\nValue 2: Suffix (e.g. -alt)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\nFormat: duration, intensity"],
		['Change Character', "Value 1: Character (Dad, BF, GF)\nValue 2: New character name"],
		['Change Scroll Speed', "Value 1: Speed multiplier\nValue 2: Transition time (seconds)"],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1)"],
		['Camera Flash', "Value 1: Color (hex)\nValue 2: Duration in beats"],
		['Change Camera Zoom', "Value 1: New zoom value\nValue 2: Duration in beats"],
		['Set Camera Speed', "Value 1: New camera lerp speed"]
	];

	var _file:FileReference;
	var UI_box:FlxUITabMenu;

	public static var goToPlayState:Bool = false;
	public static var curSec:Int         = 0;
	public static var lastSection:Int    = 0;
	private static var lastSong:String   = '';

	var bpmTxt:FlxText;
	var camPos:FlxObject;
	var strumLine:FlxSprite;
	var quant:AttachedSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote>;
	var curSong:String    = 'Test';
	var amountSteps:Int   = 0;
	var bullshitUI:FlxGroup;
	var highlight:FlxSprite;

	public static var GRID_SIZE:Int = 40;
	var CAM_OFFSET:Int              = 360;
	var dummyArrow:FlxSprite;

	var curRenderedSustains:FlxTypedGroup<FlxSprite>;
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedNoteType:FlxTypedGroup<FlxText>;
	var nextRenderedSustains:FlxTypedGroup<FlxSprite>;
	var nextRenderedNotes:FlxTypedGroup<Note>;

	var gridBG:FlxSprite;
	var nextGridBG:FlxSprite;

	var daquantspot:Int      = 0;
	var curEventSelected:Int = 0;
	var curUndoIndex:Int     = 0;
	var curRedoIndex:Int     = 0;
	var _song:SwagSong;
	var curSelectedNote:Array<Dynamic> = null;
	var playbackSpeed:Float            = 1;

	var vocals:FlxSound         = null;
	var opponentVocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;

	var value1InputText:FlxUIInputText;
	var value2InputText:FlxUIInputText;
	var currentSongName:String;
	var zoomTxt:FlxText;

	var zoomList:Array<Float> = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24];
	var curZoom:Int           = 2;

	private var blockPressWhileTypingOn:Array<FlxUIInputText>             = [];
	private var blockPressWhileTypingOnStepper:Array<FlxUINumericStepper> = [];
	private var blockPressWhileScrolling:Array<FlxUIDropDownMenu>         = [];

	var waveformSprite:FlxSprite;
	var gridLayer:FlxTypedGroup<FlxSprite>;

	public static var quantization:Int = 16;
	public static var curQuant:Int      = 3;
	public var quantizations:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];

	var text:String        = "";
	public static var vortex:Bool = false;
	public var mouseQuant:Bool    = false;

	var _beatFlash:FlxSprite        = null;
	var _selectionBox:FlxSprite     = null;
	var _statusBar:FlxText          = null;
	var _undoIndicator:FlxText      = null;
	var _sectionLabel:FlxText       = null;
	var _noteCountTxt:FlxText       = null;
	var _noteFeedbacks:Array<FlxSprite> = [];
	var _historyLog:Array<String>   = [];
	static final MAX_HISTORY:Int    = 50;

	override function create():Void
	{
		if (PlayState.SONG != null)
			_song = PlayState.SONG;
		else
		{
			Difficulty.resetList();
			_song = {
				song: 'Test', notes: [], events: [], bpm: 150.0,
				needsVoices: true, player1: 'bf', player2: 'dad',
				gfVersion: 'gf', speed: 1, stage: 'stage'
			};
			addSection();
			PlayState.SONG = _song;
		}

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
		#end

		vortex         = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing  = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.color         = 0xFF1A1A2A;
		add(bg);

		var gradBg:FlxSprite = FlxGradient.createGradientFlxSprite(
			FlxG.width, FlxG.height, [0xAA000000, 0x440A0A1A, 0xAA000000], 1, 90);
		gradBg.scrollFactor.set();
		add(gradBg);

		gridLayer      = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(1, 1, 0x00FFFFFF);
		add(waveformSprite);

		var eventIcon:FlxSprite = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('eventArrow'));
		eventIcon.antialiasing  = ClientPrefs.data.antialiasing;
		leftIcon  = new HealthIcon('bf');
		rightIcon = new HealthIcon('dad');
		eventIcon.scrollFactor.set(1, 1);
		leftIcon.scrollFactor.set(1, 1);
		rightIcon.scrollFactor.set(1, 1);
		eventIcon.setGraphicSize(30, 30);
		leftIcon.setGraphicSize(0, 45);
		rightIcon.setGraphicSize(0, 45);
		add(eventIcon);
		add(leftIcon);
		add(rightIcon);
		leftIcon.setPosition(GRID_SIZE + 10, -100);
		rightIcon.setPosition(GRID_SIZE * 5.2, -100);

		curRenderedSustains  = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes     = new FlxTypedGroup<Note>();
		curRenderedNoteType  = new FlxTypedGroup<FlxText>();
		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes    = new FlxTypedGroup<Note>();

		FlxG.mouse.visible = true;

		updateJsonData();
		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();
		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		if (curSec >= _song.notes.length) curSec = _song.notes.length - 1;

		bpmTxt = new FlxText(1000, 50, 0, "", 16);
		bpmTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		bpmTxt.borderSize = 1;
		bpmTxt.scrollFactor.set();
		add(bpmTxt);

		strumLine       = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * 9), 4);
		strumLine.color = 0xFFFFFFFF;
		add(strumLine);

		_beatFlash        = new FlxSprite(GRID_SIZE, 0).makeGraphic(Std.int(GRID_SIZE * 8), 4, 0xFFFFFFFF);
		_beatFlash.alpha  = 0;
		_beatFlash.scrollFactor.set(1, 1);
		add(_beatFlash);

		_selectionBox       = new FlxSprite().makeGraphic(GRID_SIZE + 4, GRID_SIZE + 4, 0x44FFFFFF);
		_selectionBox.alpha = 0;
		_selectionBox.scrollFactor.set(1, 1);
		add(_selectionBox);

		quant = new AttachedSprite('chart_quant', 'chart_quant');
		quant.animation.addByPrefix('q', 'chart_quant', 0, false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd       = -32;
		quant.yAdd       = 8;
		add(quant);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		for (i in 0...8)
		{
			var note:StrumNote = new StrumNote(GRID_SIZE * (i + 1), strumLine.y, i % 4, 0);
			note.setGraphicSize(GRID_SIZE, GRID_SIZE);
			note.updateHitbox();
			note.playAnim('static', true);
			strumLineNotes.add(note);
			note.scrollFactor.set(1, 1);
		}
		add(strumLineNotes);

		camPos = new FlxObject(0, 0, 1, 1);
		camPos.setPosition(strumLine.x + CAM_OFFSET, strumLine.y);

		dummyArrow             = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		dummyArrow.antialiasing = ClientPrefs.data.antialiasing;
		dummyArrow.alpha        = 0.6;
		add(dummyArrow);

		var tabs = [
			{name: "Song",     label: 'Song'},
			{name: "Section",  label: 'Section'},
			{name: "Note",     label: 'Note'},
			{name: "Events",   label: 'Events'},
			{name: "Charting", label: 'Charting'},
			{name: "Data",     label: 'Data'},
			{name: "Import",   label: 'Import'}
		];

		UI_box = new FlxUITabMenu(null, tabs, true);
		UI_box.resize(300, 400);
		UI_box.x = 640 + GRID_SIZE / 2;
		UI_box.y = 25;
		UI_box.scrollFactor.set();

		if (controls.mobileC)
			text = "Up/Down - Change strum time\nLeft/Right - Prev/next section\nHold Y - Move 4x faster\nHold F + touch arrow - Select\nV/D - Zoom in/out\nC - Test chart\nA - Play chart\nUp/Down(Right) - Sustain length\nX - Stop/Resume";
		else
			text = "W/S or Mouse Wheel - Change strum time\nA/D - Prev/next section\nLeft/Right - Change snap\nUp/Down - Snapped strum time\nHold Shift - Move 4x faster\nCtrl + click - Select note\nZ/X - Zoom in/out\nEsc - Test chart\nEnter - Play chart\nQ/E - Sustain length\nSpace - Stop/Resume\nCtrl+Z - Undo\nCtrl+S - Quick save\nCtrl+I - Import VSlice";

		var tipTextArray:Array<String> = text.split('\n');
		for (i in 0...tipTextArray.length)
		{
			var tipText:FlxText = new FlxText(UI_box.x, UI_box.y + UI_box.height + 8, 0, tipTextArray[i], 12);
			tipText.y += i * 12;
			tipText.setFormat(Paths.font("vcr.ttf"), 12, 0xFFCCCCCC, LEFT);
			tipText.scrollFactor.set();
			add(tipText);
		}
		add(UI_box);

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		addDataUI();
		addImportUI();
		updateHeads();
		updateWaveform();

		add(curRenderedSustains);
		add(curRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		if (lastSong != currentSongName) changeSection();
		lastSong = currentSongName;

		zoomTxt = new FlxText(10, 10, 0, "Zoom: 1 / 1", 16);
		zoomTxt.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		zoomTxt.borderSize = 1;
		zoomTxt.scrollFactor.set();
		add(zoomTxt);

		_sectionLabel = new FlxText(10, 30, 0, '', 14);
		_sectionLabel.setFormat(Paths.font('vcr.ttf'), 14, 0xFFFFCC00, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_sectionLabel.borderSize   = 1;
		_sectionLabel.scrollFactor.set();
		add(_sectionLabel);

		_noteCountTxt = new FlxText(10, 48, 0, '', 13);
		_noteCountTxt.setFormat(Paths.font('vcr.ttf'), 13, 0xFFAAFFAA, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_noteCountTxt.borderSize   = 1;
		_noteCountTxt.scrollFactor.set();
		add(_noteCountTxt);

		_statusBar = new FlxText(10, FlxG.height - 22, 0, '', 13);
		_statusBar.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_statusBar.borderSize   = 1;
		_statusBar.scrollFactor.set();
		add(_statusBar);

		_undoIndicator = new FlxText(UI_box.x, UI_box.y + UI_box.height - 20, UI_box.width, '', 12);
		_undoIndicator.setFormat(Paths.font('vcr.ttf'), 12, 0xFFAAAAAA, RIGHT);
		_undoIndicator.scrollFactor.set();
		add(_undoIndicator);

		updateGrid();

		#if mobile
		addTouchPad("LEFT_FULL", "CHART_EDITOR");
		#end

		super.create();
	}

	function _setStatus(msg:String, ?color:FlxColor):Void
	{
		if (_statusBar == null) return;
		_statusBar.text  = msg;
		_statusBar.color = color ?? FlxColor.WHITE;
		FlxTween.cancelTweensOf(_statusBar);
		_statusBar.alpha = 1;
		FlxTween.tween(_statusBar, {alpha: 0}, 2.5, {startDelay: 1.5, ease: FlxEase.quartIn});
		_historyLog.push(msg);
		if (_historyLog.length > MAX_HISTORY) _historyLog.shift();
		if (_undoIndicator != null) _undoIndicator.text = 'Undos: ${undos.length}';
	}

	function _spawnNoteFeedback(x:Float, y:Float, isDelete:Bool = false):Void
	{
		var spr:FlxSprite = new FlxSprite(x, y).makeGraphic(GRID_SIZE, GRID_SIZE, isDelete ? 0xAAFF3333 : 0xAA33FF66);
		spr.scrollFactor.set(1, 1);
		insert(members.indexOf(curRenderedNotes) + 1, spr);
		_noteFeedbacks.push(spr);
		FlxTween.tween(spr, {alpha: 0, y: y - 20}, 0.35, {ease: FlxEase.quartOut, onComplete: function(_:FlxTween):Void
		{
			remove(spr, true);
			_noteFeedbacks.remove(spr);
			spr.destroy();
		}});
	}

	function _flashBeat():Void
	{
		if (_beatFlash == null) return;
		FlxTween.cancelTweensOf(_beatFlash);
		_beatFlash.y     = strumLine.y;
		_beatFlash.alpha = 0.5;
		FlxTween.tween(_beatFlash, {alpha: 0}, 0.2, {ease: FlxEase.quartOut});
	}

	function _updateSectionLabel():Void
	{
		if (_sectionLabel == null) return;
		_sectionLabel.text = 'Section: $curSec  |  BPM: ${Std.int(Conductor.bpm)}';
		var total:Int = 0;
		for (sec in _song.notes) total += sec.sectionNotes.length;
		if (_noteCountTxt != null)
			_noteCountTxt.text = 'Notes: ${_song.notes[curSec].sectionNotes.length} this section  |  Total: $total';
	}

	function _updateSelectionBox():Void
	{
		if (_selectionBox == null || curSelectedNote == null || curSelectedNote[2] == null)
		{
			if (_selectionBox != null) _selectionBox.alpha = 0;
			return;
		}
		curRenderedNotes.forEachAlive(function(note:Note):Void
		{
			var ndCheck:Int = note.noteData;
			if (ndCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) ndCheck += 4;
			if (curSelectedNote[0] == note.strumTime && curSelectedNote[1] == ndCheck)
			{
				_selectionBox.setPosition(note.x - 2, note.y - 2);
				_selectionBox.alpha = 0.4 + Math.abs(Math.sin(haxe.Timer.stamp() * 5)) * 0.4;
			}
		});
	}

	var check_mute_inst:FlxUICheckBox            = null;
	var check_mute_vocals:FlxUICheckBox          = null;
	var check_mute_vocals_opponent:FlxUICheckBox = null;
	var check_vortex:FlxUICheckBox               = null;
	var check_warnings:FlxUICheckBox             = null;
	var playSoundBf:FlxUICheckBox                = null;
	var playSoundDad:FlxUICheckBox               = null;
	var UI_songTitle:FlxUIInputText;
	var stageDropDown:FlxUIDropDownMenu;

	#if FLX_PITCH
	var sliderRate:FlxUISlider;
	#end

	function addSongUI():Void
	{
		UI_songTitle = new FlxUIInputText(10, 10, 70, _song.song, 8);
		blockPressWhileTypingOn.push(UI_songTitle);

		var check_voices = new FlxUICheckBox(10, 25, null, null, "Has voice track", 100);
		check_voices.checked  = _song.needsVoices;
		check_voices.callback = function() { _song.needsVoices = check_voices.checked; };

		var saveButton:FlxButton    = new FlxButton(110, 8, "Save", function() { saveLevel(); });
		var quickSaveBtn:FlxButton  = new FlxButton(saveButton.x, saveButton.y + 20, 'Quick Save', function()
		{
			autosaveSong();
			_setStatus('Auto-saved!', 0xFFAAFFAA);
		});
		quickSaveBtn.color       = 0xFF336633;
		quickSaveBtn.label.color = FlxColor.WHITE;

		var reloadSong:FlxButton = new FlxButton(saveButton.x + 90, saveButton.y, "Reload Audio", function()
		{
			currentSongName = Paths.formatToSongPath(UI_songTitle.text);
			updateJsonData(); loadSong(); updateWaveform();
		});

		var reloadSongJson:FlxButton = new FlxButton(reloadSong.x, saveButton.y + 30, "Reload JSON", function()
		{
			openSubState(new Prompt('This will clear current progress.\n\nProceed?', 0, function() { loadJson(_song.song.toLowerCase()); }, null, ignoreWarnings));
		});

		var loadAutosaveBtn:FlxButton = new FlxButton(reloadSongJson.x, reloadSongJson.y + 30, 'Load Autosave', function()
		{
			PlayState.SONG = Song.parseJSONshit(FlxG.save.data.autosave);
			MusicBeatState.resetState();
		});

		var loadEventJson:FlxButton = new FlxButton(loadAutosaveBtn.x, loadAutosaveBtn.y + 30, 'Load Events', function()
		{
			var songName:String = Paths.formatToSongPath(_song.song);
			var file:String     = Paths.json(songName + '/events');
			#if sys
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsJson(songName + '/events')) || #end FileSystem.exists(file))
			#else
			if (OpenFlAssets.exists(file))
			#end
			{
				clearEvents();
				var events:SwagSong = Song.loadFromJson('events', songName);
				_song.events        = events.events;
				changeSection(curSec);
			}
		});

		var saveEvents:FlxButton = new FlxButton(110, reloadSongJson.y, 'Save Events', function() { saveEventsToFile(); });

		var clear_events:FlxButton = new FlxButton(320, 310, 'Clear events', function()
		{
			openSubState(new Prompt('This will clear events.\n\nProceed?', 0, clearEvents, null, ignoreWarnings));
		});
		clear_events.color       = FlxColor.RED;
		clear_events.label.color = FlxColor.WHITE;

		var clear_notes:FlxButton = new FlxButton(320, clear_events.y + 30, 'Clear notes', function()
		{
			openSubState(new Prompt('This will clear all notes.\n\nProceed?', 0, function()
			{
				for (sec in 0..._song.notes.length) _song.notes[sec].sectionNotes = [];
				updateGrid();
				_setStatus('All notes cleared.', 0xFFFF8888);
			}, null, ignoreWarnings));
		});
		clear_notes.color       = FlxColor.RED;
		clear_notes.label.color = FlxColor.WHITE;

		var stepperBPM:FlxUINumericStepper = new FlxUINumericStepper(10, 70, 1, 1, 1, 400, 3);
		stepperBPM.value = Conductor.bpm;
		stepperBPM.name  = 'song_bpm';
		blockPressWhileTypingOnStepper.push(stepperBPM);

		var stepperSpeed:FlxUINumericStepper = new FlxUINumericStepper(10, stepperBPM.y + 35, 0.1, 1, 0.1, 10, 2);
		stepperSpeed.value = _song.speed;
		stepperSpeed.name  = 'song_speed';
		blockPressWhileTypingOnStepper.push(stepperSpeed);

		#if MODS_ALLOWED
		var dirs:Array<String> = [Paths.mods('characters/'), Paths.mods(Mods.currentModDirectory + '/characters/'), Paths.getSharedPath('characters/')];
		for (mod in Mods.getGlobalMods()) dirs.push(Paths.mods(mod + '/characters/'));
		#else
		var dirs:Array<String> = [Paths.getSharedPath('characters/')];
		#end

		var tempArray:Array<String>   = [];
		var characters:Array<String>  = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getSharedPath());
		for (c in characters) if (c.trim().length > 0) tempArray.push(c);

		#if MODS_ALLOWED
		for (directory in dirs)
			if (FileSystem.exists(directory))
				for (file in Paths.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json'))
					{
						var cc:String = file.substr(0, file.length - 5);
						if (cc.trim().length > 0 && !cc.endsWith('-dead') && !tempArray.contains(cc))
						{ tempArray.push(cc); characters.push(cc); }
					}
				}
		#end
		tempArray = [];

		var player1DD = new FlxUIDropDownMenu(10, stepperSpeed.y + 45, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(c:String) { _song.player1 = characters[Std.parseInt(c)]; updateJsonData(); updateHeads(); });
		player1DD.selectedLabel = _song.player1;
		blockPressWhileScrolling.push(player1DD);

		var gfDD = new FlxUIDropDownMenu(player1DD.x, player1DD.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(c:String) { _song.gfVersion = characters[Std.parseInt(c)]; updateJsonData(); updateHeads(); });
		gfDD.selectedLabel = _song.gfVersion;
		blockPressWhileScrolling.push(gfDD);

		var player2DD = new FlxUIDropDownMenu(player1DD.x, gfDD.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(c:String) { _song.player2 = characters[Std.parseInt(c)]; updateJsonData(); updateHeads(); });
		player2DD.selectedLabel = _song.player2;
		blockPressWhileScrolling.push(player2DD);

		#if MODS_ALLOWED
		var stageDirs:Array<String> = [Paths.mods('stages/'), Paths.mods(Mods.currentModDirectory + '/stages/'), Paths.getSharedPath('stages/')];
		for (mod in Mods.getGlobalMods()) stageDirs.push(Paths.mods(mod + '/stages/'));
		#else
		var stageDirs:Array<String> = [Paths.getSharedPath('stages/')];
		#end

		var stageFile:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getSharedPath());
		var stages:Array<String>    = [];
		for (s in stageFile) if (s.trim().length > 0) { stages.push(s); tempArray.push(s); }
		#if MODS_ALLOWED
		for (directory in stageDirs)
			if (FileSystem.exists(directory))
				for (file in Paths.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json'))
					{
						var sc:String = file.substr(0, file.length - 5);
						if (sc.trim().length > 0 && !tempArray.contains(sc)) { tempArray.push(sc); stages.push(sc); }
					}
				}
		#end
		if (stages.length < 1) stages.push('stage');

		stageDropDown = new FlxUIDropDownMenu(player1DD.x + 140, player1DD.y, FlxUIDropDownMenu.makeStrIdLabelArray(stages, true), function(s:String) { _song.stage = stages[Std.parseInt(s)]; });
		stageDropDown.selectedLabel = _song.stage;
		blockPressWhileScrolling.push(stageDropDown);

		var tab = new FlxUI(null, UI_box);
		tab.name = "Song";
		tab.add(UI_songTitle); tab.add(check_voices); tab.add(clear_events); tab.add(clear_notes);
		tab.add(saveButton); tab.add(quickSaveBtn); tab.add(saveEvents); tab.add(reloadSong);
		tab.add(reloadSongJson); tab.add(loadAutosaveBtn); tab.add(loadEventJson);
		tab.add(stepperBPM); tab.add(stepperSpeed);
		tab.add(new FlxText(stepperBPM.x, stepperBPM.y - 15, 0, 'Song BPM:'));
		tab.add(new FlxText(stepperSpeed.x, stepperSpeed.y - 15, 0, 'Song Speed:'));
		tab.add(new FlxText(player2DD.x, player2DD.y - 15, 0, 'Opponent:'));
		tab.add(new FlxText(gfDD.x, gfDD.y - 15, 0, 'Girlfriend:'));
		tab.add(new FlxText(player1DD.x, player1DD.y - 15, 0, 'Boyfriend:'));
		tab.add(new FlxText(stageDropDown.x, stageDropDown.y - 15, 0, 'Stage:'));
		tab.add(player2DD); tab.add(gfDD); tab.add(player1DD); tab.add(stageDropDown);
		UI_box.addGroup(tab);

		initPsychCamera().follow(camPos, LOCKON, 999);
	}

	var stepperBeats:FlxUINumericStepper;
	var check_mustHitSection:FlxUICheckBox;
	var check_gfSection:FlxUICheckBox;
	var check_changeBPM:FlxUICheckBox;
	var stepperSectionBPM:FlxUINumericStepper;
	var check_altAnim:FlxUICheckBox;
	var sectionToCopy:Int = 0;
	var notesCopied:Array<Dynamic>;

	function addSectionUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Section';

		check_mustHitSection      = new FlxUICheckBox(10, 15, null, null, "Must hit section", 100);
		check_mustHitSection.name = 'check_mustHit';
		check_mustHitSection.checked = _song.notes[curSec].mustHitSection;

		check_gfSection      = new FlxUICheckBox(10, check_mustHitSection.y + 22, null, null, "GF section", 100);
		check_gfSection.name = 'check_gf';
		check_gfSection.checked = _song.notes[curSec].gfSection;

		check_altAnim         = new FlxUICheckBox(check_gfSection.x + 120, check_gfSection.y, null, null, "Alt Animation", 100);
		check_altAnim.checked = _song.notes[curSec].altAnim;
		check_altAnim.name    = 'check_altAnim';

		stepperBeats       = new FlxUINumericStepper(10, 100, 1, 4, 1, 7, 2);
		stepperBeats.value = getSectionBeats();
		stepperBeats.name  = 'section_beats';
		blockPressWhileTypingOnStepper.push(stepperBeats);

		check_changeBPM         = new FlxUICheckBox(10, stepperBeats.y + 30, null, null, 'Change BPM', 100);
		check_changeBPM.checked = _song.notes[curSec].changeBPM;
		check_changeBPM.name    = 'check_changeBPM';

		stepperSectionBPM       = new FlxUINumericStepper(10, check_changeBPM.y + 20, 1, Conductor.bpm, 0, 999, 1);
		stepperSectionBPM.value = check_changeBPM.checked ? _song.notes[curSec].bpm : Conductor.bpm;
		stepperSectionBPM.name  = 'section_bpm';
		blockPressWhileTypingOnStepper.push(stepperSectionBPM);

		var check_eventsSec:FlxUICheckBox = null;
		var check_notesSec:FlxUICheckBox  = null;

		var copyButton:FlxButton = new FlxButton(10, 190, "Copy Section", function()
		{
			notesCopied   = [];
			sectionToCopy = curSec;
			for (i in 0..._song.notes[curSec].sectionNotes.length) notesCopied.push(_song.notes[curSec].sectionNotes[i]);
			var st:Float = sectionStartTime();
			var et:Float = sectionStartTime(1);
			for (event in _song.events)
				if (et > event[0] && event[0] >= st)
				{
					var cea:Array<Dynamic> = [];
					for (i in 0...event[1].length) cea.push([event[1][i][0], event[1][i][1], event[1][i][2]]);
					notesCopied.push([event[0], -1, cea]);
				}
			_setStatus('Section copied!', 0xFFAAFFAA);
		});

		var pasteButton:FlxButton = new FlxButton(copyButton.x + 100, copyButton.y, "Paste Section", function()
		{
			if (notesCopied == null || notesCopied.length < 1) return;
			var addToTime:Float = Conductor.stepCrochet * (getSectionBeats() * 4 * (curSec - sectionToCopy));
			for (note in notesCopied)
			{
				var nst:Float = note[0] + addToTime;
				if (note[1] < 0)
				{
					if (check_eventsSec.checked)
					{
						var cea:Array<Dynamic> = [];
						for (i in 0...note[2].length) cea.push([note[2][i][0], note[2][i][1], note[2][i][2]]);
						_song.events.push([nst, cea]);
					}
				}
				else if (check_notesSec.checked)
					_song.notes[curSec].sectionNotes.push(note[4] != null ? [nst, note[1], note[2], note[3], note[4]] : [nst, note[1], note[2], note[3]]);
			}
			updateGrid();
			_setStatus('Section pasted!', 0xFFAAFFAA);
		});

		var clearSectionButton:FlxButton = new FlxButton(pasteButton.x + 100, pasteButton.y, "Clear", function()
		{
			if (check_notesSec.checked) _song.notes[curSec].sectionNotes = [];
			if (check_eventsSec.checked)
			{
				var i:Int    = _song.events.length - 1;
				var st:Float = sectionStartTime();
				var et:Float = sectionStartTime(1);
				while (i > -1)
				{
					var ev:Array<Dynamic> = _song.events[i];
					if (ev != null && et > ev[0] && ev[0] >= st) _song.events.remove(ev);
					--i;
				}
			}
			updateGrid(); updateNoteUI();
			_setStatus('Section cleared.', 0xFFFF8888);
		});
		clearSectionButton.color       = FlxColor.RED;
		clearSectionButton.label.color = FlxColor.WHITE;

		check_notesSec          = new FlxUICheckBox(10, clearSectionButton.y + 25, null, null, "Notes", 100);
		check_notesSec.checked  = true;
		check_eventsSec         = new FlxUICheckBox(check_notesSec.x + 100, check_notesSec.y, null, null, "Events", 100);
		check_eventsSec.checked = true;

		var swapSection:FlxButton = new FlxButton(10, check_notesSec.y + 40, "Swap section", function()
		{
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				note[1] = (note[1] + 4) % 8;
				_song.notes[curSec].sectionNotes[i] = note;
			}
			updateGrid();
			_setStatus('Section swapped.', 0xFFAAFFAA);
		});

		var stepperCopy:FlxUINumericStepper = null;
		var copyLastButton:FlxButton = new FlxButton(10, swapSection.y + 30, "Copy last section", function()
		{
			var value:Int = Std.int(stepperCopy.value);
			if (value == 0) return;
			var daSec = FlxMath.maxInt(curSec, value);
			for (note in _song.notes[daSec - value].sectionNotes)
			{
				var strum = note[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
				_song.notes[daSec].sectionNotes.push([strum, note[1], note[2], note[3]]);
			}
			var st:Float = sectionStartTime(-value);
			var et:Float = sectionStartTime(-value + 1);
			for (event in _song.events)
				if (et > event[0] && event[0] >= st)
				{
					var nst:Float       = event[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
					var cea:Array<Dynamic> = [];
					for (i in 0...event[1].length) cea.push([event[1][i][0], event[1][i][1], event[1][i][2]]);
					_song.events.push([nst, cea]);
				}
			updateGrid();
		});
		copyLastButton.setGraphicSize(80, 30);
		copyLastButton.updateHitbox();

		stepperCopy = new FlxUINumericStepper(copyLastButton.x + 100, copyLastButton.y, 1, 1, -999, 999, 0);
		blockPressWhileTypingOnStepper.push(stepperCopy);

		var duetButton:FlxButton = new FlxButton(10, copyLastButton.y + 45, "Duet Notes", function()
		{
			var dn:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				var b = note[1];
				b = b > 3 ? b - 4 : b + 4;
				dn.push([note[0], b, note[2], note[3]]);
			}
			for (i in dn) _song.notes[curSec].sectionNotes.push(i);
			updateGrid();
		});

		var mirrorButton:FlxButton = new FlxButton(duetButton.x + 100, duetButton.y, "Mirror Notes", function()
		{
			for (note in _song.notes[curSec].sectionNotes)
			{
				var b = 3 - (note[1] % 4);
				if (note[1] > 3) b += 4;
				note[1] = b;
			}
			updateGrid();
		});

		tab.add(new FlxText(stepperBeats.x, stepperBeats.y - 15, 0, 'Beats per Section:'));
		tab.add(stepperBeats); tab.add(stepperSectionBPM);
		tab.add(check_mustHitSection); tab.add(check_gfSection); tab.add(check_altAnim); tab.add(check_changeBPM);
		tab.add(copyButton); tab.add(pasteButton); tab.add(clearSectionButton);
		tab.add(check_notesSec); tab.add(check_eventsSec); tab.add(swapSection);
		tab.add(stepperCopy); tab.add(copyLastButton); tab.add(duetButton); tab.add(mirrorButton);
		UI_box.addGroup(tab);
	}

	var stepperSusLength:FlxUINumericStepper;
	var strumTimeInputText:FlxUIInputText;
	var noteTypeDropDown:FlxUIDropDownMenu;
	var currentType:Int = 0;

	function addNoteUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Note';

		stepperSusLength       = new FlxUINumericStepper(10, 25, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 64);
		stepperSusLength.value = 0;
		stepperSusLength.name  = 'note_susLength';
		blockPressWhileTypingOnStepper.push(stepperSusLength);

		strumTimeInputText = new FlxUIInputText(10, 65, 180, "0");
		tab.add(strumTimeInputText);
		blockPressWhileTypingOn.push(strumTimeInputText);

		var key:Int = 0;
		while (key < noteTypeList.length) { curNoteTypes.push(noteTypeList[key]); key++; }

		#if sys
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_notetypes/'))
			for (file in Paths.readDirectory(folder))
			{
				var fn:String  = file.toLowerCase().trim();
				var wl:Int     = 4;
				if ((#if LUA_ALLOWED fn.endsWith('.lua') || #end #if HSCRIPT_ALLOWED (fn.endsWith('.hx') && (wl = 3) == 3) || #end fn.endsWith('.txt')) && fn != 'readme.txt')
				{
					var fc:String = file.substr(0, file.length - wl);
					if (!curNoteTypes.contains(fc)) { curNoteTypes.push(fc); key++; }
				}
			}
		#end

		var displayNames:Array<String> = curNoteTypes.copy();
		for (i in 1...displayNames.length) displayNames[i] = i + '. ' + displayNames[i];

		noteTypeDropDown = new FlxUIDropDownMenu(10, 105, FlxUIDropDownMenu.makeStrIdLabelArray(displayNames, true), function(c:String)
		{
			currentType = Std.parseInt(c);
			if (curSelectedNote != null && curSelectedNote[1] > -1) { curSelectedNote[3] = curNoteTypes[currentType]; updateGrid(); }
		});
		blockPressWhileScrolling.push(noteTypeDropDown);

		tab.add(new FlxText(10, 10, 0, 'Sustain length:'));
		tab.add(new FlxText(10, 50, 0, 'Strum time (ms):'));
		tab.add(new FlxText(10, 90, 0, 'Note type:'));
		tab.add(stepperSusLength); tab.add(strumTimeInputText); tab.add(noteTypeDropDown);
		UI_box.addGroup(tab);
	}

	var eventDropDown:FlxUIDropDownMenu;
	var descText:FlxText;
	var selectedEventText:FlxText;

	function addEventsUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Events';

		#if LUA_ALLOWED
		var eventPushedMap:Map<String, Bool> = new Map();
		var evDirs:Array<String> = [];
		#if MODS_ALLOWED
		evDirs.push(Paths.mods('custom_events/'));
		evDirs.push(Paths.mods(Mods.currentModDirectory + '/custom_events/'));
		for (mod in Mods.getGlobalMods()) evDirs.push(Paths.mods(mod + '/custom_events/'));
		#end
		for (directory in evDirs)
			if (FileSystem.exists(directory))
				for (file in Paths.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt'))
					{
						var fc:String = file.substr(0, file.length - 4);
						if (!eventPushedMap.exists(fc)) { eventPushedMap.set(fc, true); eventStuff.push([fc, File.getContent(path)]); }
					}
				}
		eventPushedMap.clear();
		eventPushedMap = null;
		#end

		descText = new FlxText(20, 200, 0, eventStuff[0][0]);
		var leEvents:Array<String> = [];
		for (i in 0...eventStuff.length) leEvents.push(eventStuff[i][0]);

		tab.add(new FlxText(20, 30, 0, "Event:"));
		eventDropDown = new FlxUIDropDownMenu(20, 50, FlxUIDropDownMenu.makeStrIdLabelArray(leEvents, true), function(pressed:String)
		{
			var sel:Int = Std.parseInt(pressed);
			descText.text = eventStuff[sel][1];
			if (curSelectedNote != null && curSelectedNote[2] == null)
			{ curSelectedNote[1][curEventSelected][0] = eventStuff[sel][0]; updateGrid(); }
		});
		blockPressWhileScrolling.push(eventDropDown);

		tab.add(new FlxText(20, 90, 0, "Value 1:"));
		value1InputText = new FlxUIInputText(20, 110, 100, "");
		blockPressWhileTypingOn.push(value1InputText);

		tab.add(new FlxText(20, 130, 0, "Value 2:"));
		value2InputText = new FlxUIInputText(20, 150, 100, "");
		blockPressWhileTypingOn.push(value2InputText);

		var removeButton:FlxButton = new FlxButton(eventDropDown.x + eventDropDown.width + 10, eventDropDown.y, '-', function()
		{
			if (curSelectedNote != null && curSelectedNote[2] == null)
			{
				if (curSelectedNote[1].length < 2) { _song.events.remove(curSelectedNote); curSelectedNote = null; }
				else curSelectedNote[1].remove(curSelectedNote[1][curEventSelected]);
				var eg:Array<Dynamic>;
				--curEventSelected;
				if (curEventSelected < 0) curEventSelected = 0;
				else if (curSelectedNote != null && curEventSelected >= (eg = curSelectedNote[1]).length) curEventSelected = eg.length - 1;
				changeEventSelected(); updateGrid();
			}
		});
		removeButton.setGraphicSize(Std.int(removeButton.height), Std.int(removeButton.height));
		removeButton.updateHitbox();
		removeButton.color = FlxColor.RED; removeButton.label.color = FlxColor.WHITE; removeButton.label.size = 12;
		setAllLabelsOffset(removeButton, -30, 0);
		tab.add(removeButton);

		var addButton:FlxButton = new FlxButton(removeButton.x + removeButton.width + 10, removeButton.y, '+', function()
		{
			if (curSelectedNote != null && curSelectedNote[2] == null) { curSelectedNote[1].push(['', '', '']); changeEventSelected(1); updateGrid(); }
		});
		addButton.setGraphicSize(Std.int(removeButton.width), Std.int(removeButton.height));
		addButton.updateHitbox();
		addButton.color = FlxColor.GREEN; addButton.label.color = FlxColor.WHITE; addButton.label.size = 12;
		setAllLabelsOffset(addButton, -30, 0);
		tab.add(addButton);

		var moveLeftButton:FlxButton = new FlxButton(addButton.x + addButton.width + 20, addButton.y, '<', function() { changeEventSelected(-1); });
		moveLeftButton.setGraphicSize(Std.int(addButton.width), Std.int(addButton.height));
		moveLeftButton.updateHitbox(); moveLeftButton.label.size = 12;
		setAllLabelsOffset(moveLeftButton, -30, 0);
		tab.add(moveLeftButton);

		var moveRightButton:FlxButton = new FlxButton(moveLeftButton.x + moveLeftButton.width + 10, moveLeftButton.y, '>', function() { changeEventSelected(1); });
		moveRightButton.setGraphicSize(Std.int(moveLeftButton.width), Std.int(moveLeftButton.height));
		moveRightButton.updateHitbox(); moveRightButton.label.size = 12;
		setAllLabelsOffset(moveRightButton, -30, 0);
		tab.add(moveRightButton);

		selectedEventText = new FlxText(addButton.x - 100, addButton.y + addButton.height + 6, (moveRightButton.x - addButton.x) + 186, 'Selected Event: None');
		selectedEventText.alignment = CENTER;
		tab.add(selectedEventText);
		tab.add(descText); tab.add(value1InputText); tab.add(value2InputText); tab.add(eventDropDown);
		UI_box.addGroup(tab);
	}

	function changeEventSelected(change:Int = 0):Void
	{
		if (curSelectedNote != null && curSelectedNote[2] == null)
		{
			curEventSelected += change;
			if (curEventSelected < 0) curEventSelected = Std.int(curSelectedNote[1].length) - 1;
			else if (curEventSelected >= curSelectedNote[1].length) curEventSelected = 0;
			selectedEventText.text = 'Selected Event: ' + (curEventSelected + 1) + ' / ' + curSelectedNote[1].length;
		}
		else { curEventSelected = 0; selectedEventText.text = 'Selected Event: None'; }
		updateNoteUI();
	}

	function setAllLabelsOffset(button:FlxButton, x:Float, y:Float):Void
	{
		for (point in button.labelOffsets) point.set(x, y);
	}

	var metronome:FlxUICheckBox;
	var mouseScrollingQuant:FlxUICheckBox;
	var metronomeStepper:FlxUINumericStepper;
	var metronomeOffsetStepper:FlxUINumericStepper;
	var disableAutoScrolling:FlxUICheckBox;
	var instVolume:FlxUINumericStepper;
	var voicesVolume:FlxUINumericStepper;
	var voicesOppVolume:FlxUINumericStepper;

	function addChartingUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Charting';

		#if (desktop || mobile)
		if (FlxG.save.data.chart_waveformInst     == null) FlxG.save.data.chart_waveformInst     = false;
		if (FlxG.save.data.chart_waveformVoices   == null) FlxG.save.data.chart_waveformVoices   = false;
		if (FlxG.save.data.chart_waveformOppVoices == null) FlxG.save.data.chart_waveformOppVoices = false;

		var wfInst:FlxUICheckBox = null;
		var wfVoc:FlxUICheckBox  = null;
		var wfOpp:FlxUICheckBox  = null;

		wfInst = new FlxUICheckBox(10, 90, null, null, "Waveform\n(Inst)", 85);
		wfInst.checked  = FlxG.save.data.chart_waveformInst;
		wfInst.callback = function() { wfVoc.checked = false; wfOpp.checked = false; FlxG.save.data.chart_waveformVoices = false; FlxG.save.data.chart_waveformOppVoices = false; FlxG.save.data.chart_waveformInst = wfInst.checked; updateWaveform(); };

		wfVoc = new FlxUICheckBox(wfInst.x + 100, wfInst.y, null, null, "Waveform\n(Vocals)", 85);
		wfVoc.checked  = FlxG.save.data.chart_waveformVoices && !wfInst.checked;
		wfVoc.callback = function() { wfInst.checked = false; wfOpp.checked = false; FlxG.save.data.chart_waveformInst = false; FlxG.save.data.chart_waveformOppVoices = false; FlxG.save.data.chart_waveformVoices = wfVoc.checked; updateWaveform(); };

		wfOpp = new FlxUICheckBox(wfInst.x + 200, wfInst.y, null, null, "Waveform\n(Opp.)", 85);
		wfOpp.checked  = FlxG.save.data.chart_waveformOppVoices && !wfVoc.checked;
		wfOpp.callback = function() { wfInst.checked = false; wfVoc.checked = false; FlxG.save.data.chart_waveformInst = false; FlxG.save.data.chart_waveformVoices = false; FlxG.save.data.chart_waveformOppVoices = wfOpp.checked; updateWaveform(); };
		#end

		check_mute_inst         = new FlxUICheckBox(10, 280, null, null, "Mute Instrumental (in editor)", 100);
		check_mute_inst.checked = false;
		check_mute_inst.callback = function() { FlxG.sound.music.volume = check_mute_inst.checked ? 0 : instVolume.value; };

		mouseScrollingQuant = new FlxUICheckBox(10, 190, null, null, "Mouse Scrolling Quantization", 100);
		if (FlxG.save.data.mouseScrollingQuant == null) FlxG.save.data.mouseScrollingQuant = false;
		mouseScrollingQuant.checked  = FlxG.save.data.mouseScrollingQuant;
		mouseScrollingQuant.callback = function() { FlxG.save.data.mouseScrollingQuant = mouseScrollingQuant.checked; mouseQuant = mouseScrollingQuant.checked; };

		check_vortex = new FlxUICheckBox(10, 160, null, null, "Vortex Editor (BETA)", 100);
		if (FlxG.save.data.chart_vortex == null) FlxG.save.data.chart_vortex = false;
		check_vortex.checked  = FlxG.save.data.chart_vortex;
		check_vortex.callback = function() { FlxG.save.data.chart_vortex = check_vortex.checked; vortex = check_vortex.checked; reloadGridLayer(); };

		check_warnings = new FlxUICheckBox(10, 120, null, null, "Ignore Progress Warnings", 100);
		if (FlxG.save.data.ignoreWarnings == null) FlxG.save.data.ignoreWarnings = false;
		check_warnings.checked  = FlxG.save.data.ignoreWarnings;
		check_warnings.callback = function() { FlxG.save.data.ignoreWarnings = check_warnings.checked; ignoreWarnings = check_warnings.checked; };

		check_mute_vocals          = new FlxUICheckBox(check_mute_inst.x, check_mute_inst.y + 30, null, null, "Mute Main Vocals", 100);
		check_mute_vocals.checked  = false;
		check_mute_vocals.callback = function() { if (vocals != null) vocals.volume = check_mute_vocals.checked ? 0 : voicesVolume.value; };

		check_mute_vocals_opponent          = new FlxUICheckBox(check_mute_vocals.x + 120, check_mute_vocals.y, null, null, "Mute Opp. Vocals", 100);
		check_mute_vocals_opponent.checked  = false;
		check_mute_vocals_opponent.callback = function() { if (opponentVocals != null) opponentVocals.volume = check_mute_vocals_opponent.checked ? 0 : voicesOppVolume.value; };

		playSoundBf = new FlxUICheckBox(check_mute_inst.x, check_mute_vocals.y + 30, null, null, 'Play Sound (BF notes)', 100, function() { FlxG.save.data.chart_playSoundBf = playSoundBf.checked; });
		if (FlxG.save.data.chart_playSoundBf == null) FlxG.save.data.chart_playSoundBf = false;
		playSoundBf.checked = FlxG.save.data.chart_playSoundBf;

		playSoundDad = new FlxUICheckBox(check_mute_inst.x + 120, playSoundBf.y, null, null, 'Play Sound (Opp notes)', 100, function() { FlxG.save.data.chart_playSoundDad = playSoundDad.checked; });
		if (FlxG.save.data.chart_playSoundDad == null) FlxG.save.data.chart_playSoundDad = false;
		playSoundDad.checked = FlxG.save.data.chart_playSoundDad;

		metronome = new FlxUICheckBox(10, 15, null, null, "Metronome Enabled", 100, function() { FlxG.save.data.chart_metronome = metronome.checked; });
		if (FlxG.save.data.chart_metronome == null) FlxG.save.data.chart_metronome = false;
		metronome.checked = FlxG.save.data.chart_metronome;

		metronomeStepper       = new FlxUINumericStepper(15, 55, 5, _song.bpm, 1, 1500, 1);
		metronomeOffsetStepper = new FlxUINumericStepper(metronomeStepper.x + 100, metronomeStepper.y, 25, 0, 0, 1000, 1);
		blockPressWhileTypingOnStepper.push(metronomeStepper);
		blockPressWhileTypingOnStepper.push(metronomeOffsetStepper);

		disableAutoScrolling = new FlxUICheckBox(metronome.x + 120, metronome.y, null, null, "Disable Autoscroll", 120, function() { FlxG.save.data.chart_noAutoScroll = disableAutoScrolling.checked; });
		if (FlxG.save.data.chart_noAutoScroll == null) FlxG.save.data.chart_noAutoScroll = false;
		disableAutoScrolling.checked = FlxG.save.data.chart_noAutoScroll;

		instVolume       = new FlxUINumericStepper(metronomeStepper.x, 250, 0.1, 1, 0, 1, 1);
		instVolume.value = FlxG.sound.music.volume;
		instVolume.name  = 'inst_volume';
		blockPressWhileTypingOnStepper.push(instVolume);

		voicesVolume       = new FlxUINumericStepper(instVolume.x + 100, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesVolume.value = vocals.volume;
		voicesVolume.name  = 'voices_volume';
		blockPressWhileTypingOnStepper.push(voicesVolume);

		voicesOppVolume       = new FlxUINumericStepper(instVolume.x + 200, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesOppVolume.value = vocals.volume;
		voicesOppVolume.name  = 'voices_opp_volume';
		blockPressWhileTypingOnStepper.push(voicesOppVolume);

		#if FLX_PITCH
		sliderRate = new FlxUISlider(this, 'playbackSpeed', 120, 120, 0.5, 3, 150, null, 5, FlxColor.WHITE, FlxColor.BLACK);
		sliderRate.nameLabel.text = 'Playback Rate';
		tab.add(sliderRate);
		#end

		tab.add(new FlxText(metronomeStepper.x, metronomeStepper.y - 15, 0, 'BPM:'));
		tab.add(new FlxText(metronomeOffsetStepper.x, metronomeOffsetStepper.y - 15, 0, 'Offset (ms):'));
		tab.add(new FlxText(instVolume.x, instVolume.y - 15, 0, 'Inst Volume'));
		tab.add(new FlxText(voicesVolume.x, voicesVolume.y - 15, 0, 'Main Vocals'));
		tab.add(new FlxText(voicesOppVolume.x, voicesOppVolume.y - 15, 0, 'Opp. Vocals'));
		tab.add(metronome); tab.add(disableAutoScrolling);
		tab.add(metronomeStepper); tab.add(metronomeOffsetStepper);
		#if (desktop || mobile)
		tab.add(wfInst); tab.add(wfVoc); tab.add(wfOpp);
		#end
		tab.add(instVolume); tab.add(voicesVolume); tab.add(voicesOppVolume);
		tab.add(check_mute_inst); tab.add(check_mute_vocals); tab.add(check_mute_vocals_opponent);
		tab.add(check_vortex); tab.add(mouseScrollingQuant); tab.add(check_warnings);
		tab.add(playSoundBf); tab.add(playSoundDad);
		UI_box.addGroup(tab);
	}

	var gameOverCharacterInputText:FlxUIInputText;
	var gameOverSoundInputText:FlxUIInputText;
	var gameOverLoopInputText:FlxUIInputText;
	var gameOverEndInputText:FlxUIInputText;
	var noteSkinInputText:FlxUIInputText;
	var noteSplashesInputText:FlxUIInputText;

	function addDataUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Data';

		gameOverCharacterInputText = new FlxUIInputText(10, 25, 150, _song.gameOverChar != null ? _song.gameOverChar : '', 8);
		blockPressWhileTypingOn.push(gameOverCharacterInputText);
		gameOverSoundInputText = new FlxUIInputText(10, gameOverCharacterInputText.y + 35, 150, _song.gameOverSound != null ? _song.gameOverSound : '', 8);
		blockPressWhileTypingOn.push(gameOverSoundInputText);
		gameOverLoopInputText = new FlxUIInputText(10, gameOverSoundInputText.y + 35, 150, _song.gameOverLoop != null ? _song.gameOverLoop : '', 8);
		blockPressWhileTypingOn.push(gameOverLoopInputText);
		gameOverEndInputText = new FlxUIInputText(10, gameOverLoopInputText.y + 35, 150, _song.gameOverEnd != null ? _song.gameOverEnd : '', 8);
		blockPressWhileTypingOn.push(gameOverEndInputText);

		var check_disableNoteRGB = new FlxUICheckBox(10, 170, null, null, "Disable Note RGB", 100);
		check_disableNoteRGB.checked  = (_song.disableNoteRGB == true);
		check_disableNoteRGB.callback = function() { _song.disableNoteRGB = check_disableNoteRGB.checked; updateGrid(); };

		noteSkinInputText = new FlxUIInputText(10, 280, 150, _song.arrowSkin != null ? _song.arrowSkin : '', 8);
		blockPressWhileTypingOn.push(noteSkinInputText);
		noteSplashesInputText = new FlxUIInputText(noteSkinInputText.x, noteSkinInputText.y + 35, 150, _song.splashSkin != null ? _song.splashSkin : '', 8);
		blockPressWhileTypingOn.push(noteSplashesInputText);

		var reloadNotesButton:FlxButton = new FlxButton(noteSplashesInputText.x + 5, noteSplashesInputText.y + 20, 'Change Notes', function() { _song.arrowSkin = noteSkinInputText.text; updateGrid(); });

		tab.add(gameOverCharacterInputText); tab.add(gameOverSoundInputText);
		tab.add(gameOverLoopInputText); tab.add(gameOverEndInputText);
		tab.add(check_disableNoteRGB); tab.add(reloadNotesButton);
		tab.add(noteSkinInputText); tab.add(noteSplashesInputText);
		tab.add(new FlxText(gameOverCharacterInputText.x, gameOverCharacterInputText.y - 15, 0, 'Game Over Character:'));
		tab.add(new FlxText(gameOverSoundInputText.x, gameOverSoundInputText.y - 15, 0, 'Game Over Death Sound:'));
		tab.add(new FlxText(gameOverLoopInputText.x, gameOverLoopInputText.y - 15, 0, 'Game Over Loop Music:'));
		tab.add(new FlxText(gameOverEndInputText.x, gameOverEndInputText.y - 15, 0, 'Game Over Retry Music:'));
		tab.add(new FlxText(noteSkinInputText.x, noteSkinInputText.y - 15, 0, 'Note Texture:'));
		tab.add(new FlxText(noteSplashesInputText.x, noteSplashesInputText.y - 15, 0, 'Note Splashes Texture:'));
		UI_box.addGroup(tab);
	}

	var importDifficultyDropDown:FlxUIDropDownMenu;
	var importResultTxt:FlxText;

	function addImportUI():Void
	{
		var tab = new FlxUI(null, UI_box);
		tab.name = 'Import';

		importResultTxt = new FlxText(10, 200, 280, '', 12);
		importResultTxt.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		importResultTxt.borderSize = 1;

		var diffNames:Array<String>  = ['normal', 'easy', 'hard'];
		importDifficultyDropDown = new FlxUIDropDownMenu(10, 30, FlxUIDropDownMenu.makeStrIdLabelArray(diffNames, true), function(_:String) {});
		importDifficultyDropDown.selectedLabel = 'normal';
		blockPressWhileScrolling.push(importDifficultyDropDown);

		var importVSliceBtn:FlxButton = new FlxButton(10, 80, 'Import VSlice Chart', function()
		{
			#if sys
			var diff:String     = importDifficultyDropDown.selectedLabel;
			var songFmt:String  = Paths.formatToSongPath(_song.song);
			var songPath:String = Paths.getSharedPath('data/$songFmt/$songFmt-chart.json');
			#if MODS_ALLOWED
			var modPath:String = Paths.modFolders('data/$songFmt/$songFmt-chart.json');
			if (FileSystem.exists(modPath)) songPath = modPath;
			#end
			if (!FileSystem.exists(songPath))
			{
				importResultTxt.text  = 'VSlice chart not found:\n$songPath';
				importResultTxt.color = FlxColor.RED;
				return;
			}
			var converted = ChartVSlice.load(songPath, diff);
			if (converted == null || !converted.valid)
			{
				importResultTxt.text  = 'Failed to parse VSlice chart.';
				importResultTxt.color = FlxColor.RED;
				return;
			}
			openSubState(new Prompt('Import VSlice chart?\nThis replaces current notes.\n\nProceed?', 0, function()
			{
				for (sec in 0..._song.notes.length) _song.notes[sec].sectionNotes = [];
				for (note in converted.notes)
				{
					var secDur:Float = Conductor.stepCrochet * getSectionBeats() * 4;
					var secIdx:Int   = Math.floor(note.time / secDur);
					while (_song.notes.length <= secIdx) addSection();
					var lane:Int = note.isPlayer ? (note.data % 4) + 4 : note.data % 4;
					_song.notes[secIdx].sectionNotes.push([note.time, lane, note.length, note.noteType]);
					_song.notes[secIdx].mustHitSection = note.isPlayer;
				}
				_song.speed = converted.scrollSpeed;
				updateGrid(); changeSection(curSec);
				importResultTxt.text  = 'Imported! Notes: ${converted.notes.length}';
				importResultTxt.color = 0xFFAAFFAA;
				_setStatus('VSlice chart imported!', 0xFFAAFFAA);
			}, null, true));
			#else
			importResultTxt.text  = 'File system not available.';
			importResultTxt.color = FlxColor.RED;
			#end
		});
		importVSliceBtn.setGraphicSize(150, 30);
		importVSliceBtn.updateHitbox();

		var infoTxt = new FlxText(10, 120, 280, 'VSlice chart file expected at:\ndata/songname/songname-chart.json\n\nThis overwrites all notes.', 11);
		infoTxt.setFormat(Paths.font('vcr.ttf'), 11, 0xFFCCCCCC, LEFT);

		tab.add(new FlxText(10, 10, 0, 'Difficulty to import:', 14));
		tab.add(importDifficultyDropDown); tab.add(importVSliceBtn);
		tab.add(infoTxt); tab.add(importResultTxt);
		UI_box.addGroup(tab);
	}

	function loadSong():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		if (vocals != null)         { vocals.stop(); vocals.destroy(); }
		if (opponentVocals != null) { opponentVocals.stop(); opponentVocals.destroy(); }

		vocals         = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			var pv = Paths.voices(currentSongName, (characterData.vocalsP1 == null || characterData.vocalsP1.length < 1) ? 'Player' : characterData.vocalsP1);
			vocals.loadEmbedded(pv != null ? pv : Paths.voices(currentSongName));
		}
		vocals.autoDestroy = false;
		FlxG.sound.list.add(vocals);

		opponentVocals = new FlxSound();
		try
		{
			var ov = Paths.voices(currentSongName, (characterData.vocalsP2 == null || characterData.vocalsP2.length < 1) ? 'Opponent' : characterData.vocalsP2);
			if (ov != null) opponentVocals.loadEmbedded(ov);
		}
		opponentVocals.autoDestroy = false;
		FlxG.sound.list.add(opponentVocals);

		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time  = Conductor.songPosition;

		var curTime:Float = 0;
		if (_song.notes.length <= 1)
			while (curTime < FlxG.sound.music.length) { addSection(); curTime += (60 / _song.bpm) * 4000; }
	}

	var playtesting:Bool            = false;
	var playtestingTime:Float       = 0;
	var playtestingOnComplete:Void->Void = null;

	override function closeSubState():Void
	{
		if (playtesting)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time       = playtestingTime;
			FlxG.sound.music.onComplete = playtestingOnComplete;
			if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
			if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;
			if (vocals != null) { vocals.pause(); vocals.time = playtestingTime; if (voicesVolume != null) vocals.volume = voicesVolume.value; if (check_mute_vocals != null && check_mute_vocals.checked) vocals.volume = 0; }
			if (opponentVocals != null) { opponentVocals.pause(); opponentVocals.time = playtestingTime; if (voicesOppVolume != null) opponentVocals.volume = voicesOppVolume.value; if (check_mute_vocals_opponent != null && check_mute_vocals_opponent.checked) opponentVocals.volume = 0; }
			#if DISCORD_ALLOWED
			DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
			#end
		}
		#if mobile
		touchPad.active = touchPad.visible = true;
		#end
		super.closeSubState();
	}

	function generateSong():Void
	{
		FlxG.sound.playMusic(Paths.inst(currentSongName), 0.6);
		FlxG.sound.music.autoDestroy = false;
		if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
		if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;
		FlxG.sound.music.onComplete = function()
		{
			FlxG.sound.music.pause();
			Conductor.songPosition = 0;
			if (vocals != null)         { vocals.pause(); vocals.time = 0; }
			if (opponentVocals != null) { opponentVocals.pause(); opponentVocals.time = 0; }
			changeSection(); curSec = 0; updateGrid(); updateSectionUI();
			if (vocals != null) vocals.play();
			if (opponentVocals != null) opponentVocals.play();
		};
	}

	function generateUI():Void
	{
		while (bullshitUI.members.length > 0) bullshitUI.remove(bullshitUI.members[0], true);
	}

	override function getEvent(id:String, sender:Dynamic, data:Dynamic, ?params:Array<Dynamic>):Void
	{
		if (id == FlxUICheckBox.CLICK_EVENT)
		{
			var check:FlxUICheckBox = cast sender;
			switch (check.getLabel().text)
			{
				case 'Must hit section': _song.notes[curSec].mustHitSection = check.checked; updateGrid(); updateHeads();
				case 'GF section':       _song.notes[curSec].gfSection      = check.checked; updateGrid(); updateHeads();
				case 'Change BPM':       _song.notes[curSec].changeBPM      = check.checked;
				case "Alt Animation":    _song.notes[curSec].altAnim        = check.checked;
			}
		}
		else if (id == FlxUINumericStepper.CHANGE_EVENT && (sender is FlxUINumericStepper))
		{
			var nums:FlxUINumericStepper = cast sender;
			switch (nums.name)
			{
				case 'section_beats':  _song.notes[curSec].sectionBeats = nums.value; reloadGridLayer();
				case 'song_speed':     _song.speed = nums.value;
				case 'song_bpm':       _song.bpm = nums.value; Conductor.mapBPMChanges(_song); Conductor.bpm = nums.value; stepperSusLength.stepSize = Math.ceil(Conductor.stepCrochet / 2); updateGrid();
				case 'note_susLength': if (curSelectedNote != null && curSelectedNote[2] != null) { curSelectedNote[2] = nums.value; updateGrid(); }
				case 'section_bpm':    _song.notes[curSec].bpm = nums.value; updateGrid();
				case 'inst_volume':    FlxG.sound.music.volume = nums.value; if (check_mute_inst.checked) FlxG.sound.music.volume = 0;
				case 'voices_volume':  vocals.volume = nums.value; if (check_mute_vocals.checked) vocals.volume = 0;
				case 'voices_opp_volume': opponentVocals.volume = nums.value; if (check_mute_vocals_opponent.checked) opponentVocals.volume = 0;
			}
		}
		else if (id == FlxUIInputText.CHANGE_EVENT && (sender is FlxUIInputText))
		{
			if      (sender == noteSplashesInputText)      _song.splashSkin    = noteSplashesInputText.text;
			else if (sender == noteSkinInputText)          _song.arrowSkin     = noteSkinInputText.text;
			else if (sender == gameOverCharacterInputText) _song.gameOverChar   = gameOverCharacterInputText.text;
			else if (sender == gameOverSoundInputText)     _song.gameOverSound  = gameOverSoundInputText.text;
			else if (sender == gameOverLoopInputText)      _song.gameOverLoop   = gameOverLoopInputText.text;
			else if (sender == gameOverEndInputText)       _song.gameOverEnd    = gameOverEndInputText.text;
			else if (curSelectedNote != null)
			{
				if (sender == value1InputText && curSelectedNote[1][curEventSelected] != null) { curSelectedNote[1][curEventSelected][1] = value1InputText.text; updateGrid(); }
				else if (sender == value2InputText && curSelectedNote[1][curEventSelected] != null) { curSelectedNote[1][curEventSelected][2] = value2InputText.text; updateGrid(); }
				else if (sender == strumTimeInputText) { var v:Float = Std.parseFloat(strumTimeInputText.text); if (Math.isNaN(v)) v = 0; curSelectedNote[0] = v; updateGrid(); }
			}
		}
		else if (id == FlxUISlider.CHANGE_EVENT && (sender is FlxUISlider))
		{
			switch (sender) { case 'playbackSpeed': playbackSpeed = #if FLX_PITCH Std.int(sliderRate.value) #else 1.0 #end; }
		}
	}

	function sectionStartTime(add:Int = 0):Float
	{
		var daBPM:Float = _song.bpm;
		var daPos:Float = 0;
		for (i in 0...curSec + add)
			if (_song.notes[i] != null) { if (_song.notes[i].changeBPM) daBPM = _song.notes[i].bpm; daPos += getSectionBeats(i) * (1000 * 60 / daBPM); }
		return daPos;
	}

	var lastConductorPos:Float = 0;
	var colorSine:Float        = 0;

	override function update(elapsed:Float):Void
	{
		curStep = recalculateSteps();

		if (FlxG.sound.music.time < 0) { FlxG.sound.music.pause(); FlxG.sound.music.time = 0; }
		else if (FlxG.sound.music.time > FlxG.sound.music.length) { FlxG.sound.music.pause(); FlxG.sound.music.time = 0; changeSection(); }

		Conductor.songPosition = FlxG.sound.music.time;
		_song.song             = UI_songTitle.text;

		strumLineUpdateY();
		for (i in 0...8) strumLineNotes.members[i].y = strumLine.y;
		FlxG.mouse.visible = true;
		camPos.y           = strumLine.y;

		if (!disableAutoScrolling.checked)
		{
			if (Math.ceil(strumLine.y) >= gridBG.height) { if (_song.notes[curSec + 1] == null) addSection(); changeSection(curSec + 1, false); }
			else if (strumLine.y < -10) changeSection(curSec - 1, false);
		}

		_updateSectionLabel();
		_updateSelectionBox();

		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);

		if (controls.mobileC)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch.justReleased)
				{
					if (touch.overlaps(curRenderedNotes))
						curRenderedNotes.forEachAlive(function(note:Note)
						{
							if (touch.overlaps(note))
							{
								if (touchPad.buttonF.pressed) selectNote(note);
								else if (FlxG.keys.pressed.ALT) { selectNote(note); curSelectedNote[3] = curNoteTypes[currentType]; updateGrid(); }
								else deleteNote(note);
							}
						});
					else if (!touchPad.buttonF.pressed)
						if (touch.x > gridBG.x && touch.x < gridBG.x + gridBG.width && touch.y > gridBG.y && touch.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
							addNote();
				}
				if (touch.x > gridBG.x && touch.x < gridBG.x + gridBG.width && touch.y > gridBG.y && touch.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
				{
					dummyArrow.visible = true;
					dummyArrow.x       = Math.floor(touch.x / GRID_SIZE) * GRID_SIZE;
					dummyArrow.y       = (FlxG.keys.pressed.SHIFT || touchPad.buttonY.pressed) ? touch.y : Math.floor(touch.y / GRID_SIZE) * GRID_SIZE;
				}
				else dummyArrow.visible = false;
			}
		}
		else
		{
			if (FlxG.mouse.justPressed)
			{
				if (FlxG.mouse.overlaps(curRenderedNotes))
					curRenderedNotes.forEachAlive(function(note:Note)
					{
						if (FlxG.mouse.overlaps(note))
						{
							if (FlxG.keys.pressed.CONTROL)    selectNote(note);
							else if (FlxG.keys.pressed.ALT)   { selectNote(note); curSelectedNote[3] = curNoteTypes[currentType]; updateGrid(); }
							else                               deleteNote(note);
						}
					});
				else if (FlxG.mouse.x > gridBG.x && FlxG.mouse.x < gridBG.x + gridBG.width && FlxG.mouse.y > gridBG.y && FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
					addNote();
			}
			if (FlxG.mouse.x > gridBG.x && FlxG.mouse.x < gridBG.x + gridBG.width && FlxG.mouse.y > gridBG.y && FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
			{
				dummyArrow.visible = true;
				dummyArrow.x       = Math.floor(FlxG.mouse.x / GRID_SIZE) * GRID_SIZE;
				dummyArrow.y       = FlxG.keys.pressed.SHIFT ? FlxG.mouse.y : Math.floor(FlxG.mouse.y / GRID_SIZE) * GRID_SIZE;
			}
			else dummyArrow.visible = false;
		}

		var blockInput:Bool = false;
		for (it in blockPressWhileTypingOn) if (it.hasFocus) { ClientPrefs.toggleVolumeKeys(false); blockInput = true; break; }
		if (!blockInput)
			for (st in blockPressWhileTypingOnStepper) { @:privateAccess var lt:FlxUIInputText = cast(st.text_field, FlxUIInputText); if (lt.hasFocus) { ClientPrefs.toggleVolumeKeys(false); blockInput = true; break; } }
		if (!blockInput) { ClientPrefs.toggleVolumeKeys(true); for (dd in blockPressWhileScrolling) if (dd.dropPanel.visible) { blockInput = true; break; } }

		if (!blockInput)
		{
			#if mobile
			if (FlxG.keys.justPressed.ESCAPE || touchPad.buttonC.justPressed)
			#else
			if (FlxG.keys.justPressed.ESCAPE)
			#end
			{
				if (FlxG.sound.music != null) FlxG.sound.music.stop();
				if (vocals != null) { vocals.pause(); vocals.volume = 0; }
				if (opponentVocals != null) { opponentVocals.pause(); opponentVocals.volume = 0; }
				autosaveSong();
				playtesting           = true;
				playtestingTime       = Conductor.songPosition;
				playtestingOnComplete = FlxG.sound.music.onComplete;
				openSubState(new states.editors.EditorPlayState(playbackSpeed));
			}
			#if mobile
			else if (FlxG.keys.justPressed.ENTER || touchPad.buttonA.justPressed)
			#else
			else if (FlxG.keys.justPressed.ENTER)
			#end
			{
				autosaveSong();
				FlxG.mouse.visible = false;
				PlayState.SONG     = _song;
				FlxG.sound.music.stop();
				if (vocals != null) vocals.stop();
				if (opponentVocals != null) opponentVocals.stop();
				StageData.loadDirectory(_song);
				LoadingState.loadAndSwitchState(new PlayState());
			}

			if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S) { autosaveSong(); _setStatus('Quick saved!', 0xFFAAFFAA); }
			if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z) undo();
			if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.I) { UI_box.selected_tab = 6; _setStatus('Import tab opened. (Ctrl+I)', 0xFFFFCC00); }

			if (curSelectedNote != null && curSelectedNote[1] > -1)
			{
				#if mobile
				if (touchPad.buttonDown2.justPressed || FlxG.keys.justPressed.E) changeNoteSustain(Conductor.stepCrochet);
				if (touchPad.buttonUp2.justPressed   || FlxG.keys.justPressed.Q) changeNoteSustain(-Conductor.stepCrochet);
				#else
				if (FlxG.keys.justPressed.E) changeNoteSustain(Conductor.stepCrochet);
				if (FlxG.keys.justPressed.Q) changeNoteSustain(-Conductor.stepCrochet);
				#end
			}

			#if mobile
			if (FlxG.keys.justPressed.BACKSPACE || touchPad.buttonB.justPressed)
			#else
			if (FlxG.keys.justPressed.BACKSPACE)
			#end
			{
				autosaveSong();
				PlayState.chartingMode = false;
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				FlxG.mouse.visible = false;
				return;
			}

			if (!blockInput)
			{
				if (FlxG.keys.justPressed.RIGHT) { curQuant++; if (curQuant > quantizations.length - 1) curQuant = 0; quantization = quantizations[curQuant]; }
				if (FlxG.keys.justPressed.LEFT)  { curQuant--; if (curQuant < 0) curQuant = quantizations.length - 1; quantization = quantizations[curQuant]; }
				quant.animation.play('q', true, false, curQuant);
			}

			if (vortex && !blockInput)
			{
				var cArr:Array<Bool> = [FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR, FlxG.keys.justPressed.FIVE, FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT];
				if (cArr.contains(true)) for (i in 0...cArr.length) if (cArr[i]) doANoteThing(Conductor.songPosition, i, currentType);
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
				{
					FlxG.sound.music.pause(); updateCurStep();
					var beat:Float = curDecBeat; var snap:Float = quantization / 4; var inc:Float = 1 / snap;
					var feces:Float = FlxG.keys.pressed.UP ? Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) - inc) : Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) + inc);
					FlxTween.tween(FlxG.sound.music, {time: feces}, 0.1, {ease: FlxEase.circOut});
					pauseAndSetVocalsTime();
				}
			}

			if (!vortex && (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN))
			{
				FlxG.sound.music.pause();
				var beat:Float = curDecBeat; var snap:Float = quantization / 4; var inc:Float = 1 / snap;
				FlxG.sound.music.time = FlxG.keys.pressed.UP ? Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) - inc) : Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) + inc);
			}

			var shiftThing:Int = (FlxG.keys.pressed.SHIFT #if mobile || (touchPad != null && touchPad.buttonY.pressed) #end) ? 4 : 1;
			#if mobile
			if (FlxG.keys.justPressed.D || touchPad.buttonRight.justPressed) changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A || touchPad.buttonLeft.justPressed)  changeSection(curSec <= 0 ? _song.notes.length - 1 : curSec - shiftThing);
			#else
			if (FlxG.keys.justPressed.D) changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A) changeSection(curSec <= 0 ? _song.notes.length - 1 : curSec - shiftThing);
			#end

			if (!controls.mobileC && FlxG.mouse.wheel != 0)
			{
				FlxG.sound.music.pause();
				if (!mouseQuant) FlxG.sound.music.time -= FlxG.mouse.wheel * Conductor.stepCrochet * 0.8;
				else
				{
					var beat:Float = curDecBeat; var snap:Float = quantization / 4; var inc:Float = 1 / snap;
					FlxG.sound.music.time = FlxG.mouse.wheel > 0 ? Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) - inc) : Conductor.beatToSeconds(CoolUtil.quantize(beat, snap) + inc);
				}
				pauseAndSetVocalsTime();
			}

			#if mobile
			if ((FlxG.keys.pressed.W || FlxG.keys.pressed.S) || (touchPad.buttonUp.pressed || touchPad.buttonDown.pressed))
			#else
			if (FlxG.keys.pressed.W || FlxG.keys.pressed.S)
			#end
			{
				FlxG.sound.music.pause();
				var hs:Float = FlxG.keys.pressed.CONTROL ? 0.25 : ((FlxG.keys.pressed.SHIFT #if mobile || touchPad.buttonY.pressed #end) ? 4 : 1);
				FlxG.sound.music.time += 700 * FlxG.elapsed * hs * ((FlxG.keys.pressed.W #if mobile || touchPad.buttonUp.pressed #end) ? -1 : 1);
				pauseAndSetVocalsTime();
			}

			#if mobile
			if (FlxG.keys.justPressed.SPACE || touchPad.buttonX.justPressed)
			#else
			if (FlxG.keys.justPressed.SPACE)
			#end
			{
				pauseAndSetVocalsTime();
				if (!FlxG.sound.music.playing) { FlxG.sound.music.play(); if (vocals != null) vocals.play(); if (opponentVocals != null) opponentVocals.play(); }
				else FlxG.sound.music.pause();
			}

			if (!FlxG.keys.pressed.ALT && FlxG.keys.justPressed.R)
			{
				if (FlxG.keys.pressed.SHIFT) resetSection(true); else resetSection();
			}
		}
		else if (FlxG.keys.justPressed.ENTER)
			for (i in 0...blockPressWhileTypingOn.length) if (blockPressWhileTypingOn[i].hasFocus) blockPressWhileTypingOn[i].hasFocus = false;

		strumLineNotes.visible = quant.visible = vortex;

		if (FlxG.sound.music.time < 0) { FlxG.sound.music.pause(); FlxG.sound.music.time = 0; }
		else if (FlxG.sound.music.time > FlxG.sound.music.length) { FlxG.sound.music.pause(); FlxG.sound.music.time = 0; changeSection(); }

		Conductor.songPosition = FlxG.sound.music.time;
		strumLineUpdateY();
		camPos.y = strumLine.y;
		for (i in 0...8) { strumLineNotes.members[i].y = strumLine.y; strumLineNotes.members[i].alpha = FlxG.sound.music.playing ? 1 : 0.35; }

		#if FLX_PITCH
		var hS = FlxG.keys.pressed.SHIFT; var hLB = FlxG.keys.pressed.LBRACKET; var hRB = FlxG.keys.pressed.RBRACKET;
		var pLB = FlxG.keys.justPressed.LBRACKET; var pRB = FlxG.keys.justPressed.RBRACKET;
		if (!hS && pLB || hS && hLB) playbackSpeed -= 0.01;
		if (!hS && pRB || hS && hRB) playbackSpeed += 0.01;
		#if mobile
		if (touchPad.buttonG.justPressed || (FlxG.keys.pressed.ALT && (pLB || pRB || hLB || hRB))) playbackSpeed = 1;
		#else
		if (FlxG.keys.pressed.ALT && (pLB || pRB || hLB || hRB)) playbackSpeed = 1;
		#end
		playbackSpeed = FlxMath.bound(playbackSpeed, 0.5, 3);
		FlxG.sound.music.pitch = playbackSpeed; vocals.pitch = playbackSpeed; opponentVocals.pitch = playbackSpeed;
		#end

		bpmTxt.text =
			Std.string(FlxMath.roundDecimal(Conductor.songPosition / 1000, 2)) + " / " + Std.string(FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2)) +
			"\nSection: " + curSec + "\nBeat: " + Std.string(curDecBeat).substring(0, 4) + "\nStep: " + curStep + "\nSnap: " + quantization + "th";

		var playedSound:Array<Bool> = [false, false, false, false];
		curRenderedNotes.forEachAlive(function(note:Note)
		{
			note.alpha = 1;
			if (curSelectedNote != null)
			{
				var ndc:Int = note.noteData;
				if (ndc > -1 && note.mustPress != _song.notes[curSec].mustHitSection) ndc += 4;
				if (curSelectedNote[0] == note.strumTime && ((curSelectedNote[2] == null && ndc < 0) || (curSelectedNote[2] != null && curSelectedNote[1] == ndc)))
				{
					colorSine += elapsed;
					var cv:Float = 0.7 + Math.sin(Math.PI * colorSine) * 0.3;
					note.color = FlxColor.fromRGBFloat(cv, cv, cv, 0.999);
				}
			}
			if (note.strumTime <= Conductor.songPosition)
			{
				note.alpha = 0.4;
				if (note.strumTime > lastConductorPos && FlxG.sound.music.playing && note.noteData > -1)
				{
					var data:Int = note.noteData % 4;
					var ndc:Int  = note.noteData;
					if (ndc > -1 && note.mustPress != _song.notes[curSec].mustHitSection) ndc += 4;
					strumLineNotes.members[ndc].playAnim('confirm', true);
					strumLineNotes.members[ndc].resetAnim = ((note.sustainLength / 1000) + 0.15) / playbackSpeed;
					if (!playedSound[data] && note.hitsoundChartEditor && ((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress)))
					{
						var sp = note.hitsound;
						if (_song.player1 == 'gf') sp = 'GF_' + Std.string(data + 1);
						FlxG.sound.play(Paths.sound(sp)).pan = note.noteData < 4 ? -0.3 : 0.3;
						playedSound[data] = true;
					}
				}
			}
		});

		if (metronome.checked && lastConductorPos != Conductor.songPosition)
		{
			var mi:Float = 60 / metronomeStepper.value;
			var ms:Int   = Math.floor(((Conductor.songPosition + metronomeOffsetStepper.value) / mi) / 1000);
			var lms:Int  = Math.floor(((lastConductorPos + metronomeOffsetStepper.value) / mi) / 1000);
			if (ms != lms) { FlxG.sound.play(Paths.sound('Metronome_Tick')); _flashBeat(); }
		}

		lastConductorPos = Conductor.songPosition;
		super.update(elapsed);
	}

	function pauseAndSetVocalsTime():Void
	{
		if (vocals != null)         { vocals.pause(); vocals.time = FlxG.sound.music.time; }
		if (opponentVocals != null) { opponentVocals.pause(); opponentVocals.time = FlxG.sound.music.time; }
	}

	function updateZoom():Void
	{
		var dz:Float        = zoomList[curZoom];
		var zt:String       = dz < 1 ? Math.round(1 / dz) + ' / 1' : '1 / ' + dz;
		zoomTxt.text        = 'Zoom: ' + zt;
		reloadGridLayer();
	}

	override function destroy():Void
	{
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		super.destroy();
	}

	var lastSecBeats:Float     = 0;
	var lastSecBeatsNext:Float = 0;
	var columns:Int            = 9;

	function reloadGridLayer():Void
	{
		gridLayer.clear();
		gridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats() * 4 * zoomList[curZoom]));
		gridBG.antialiasing = false;
		gridBG.scale.set(GRID_SIZE, GRID_SIZE);
		gridBG.updateHitbox();

		#if (desktop || mobile)
		if (FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices || FlxG.save.data.chart_waveformOppVoices) updateWaveform();
		#end

		var leHeight:Int    = Std.int(gridBG.height);
		var foundNextSec:Bool = false;
		if (sectionStartTime(1) <= FlxG.sound.music.length)
		{
			nextGridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats(curSec + 1) * 4 * zoomList[curZoom]));
			nextGridBG.antialiasing = false; nextGridBG.scale.set(GRID_SIZE, GRID_SIZE); nextGridBG.updateHitbox();
			leHeight = Std.int(gridBG.height + nextGridBG.height); foundNextSec = true;
		}
		else nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		gridLayer.add(nextGridBG); gridLayer.add(gridBG);

		if (foundNextSec)
		{
			var gb:FlxSprite = new FlxSprite(0, gridBG.height).makeGraphic(1, 1, FlxColor.BLACK);
			gb.setGraphicSize(Std.int(GRID_SIZE * 9), Std.int(nextGridBG.height)); gb.updateHitbox(); gb.antialiasing = false; gb.alpha = 0.4;
			gridLayer.add(gb);
		}

		var gbl:FlxSprite = new FlxSprite(gridBG.x + gridBG.width - (GRID_SIZE * 4)).makeGraphic(1, 1, FlxColor.BLACK);
		gbl.setGraphicSize(2, leHeight); gbl.updateHitbox(); gbl.antialiasing = false;
		gridLayer.add(gbl);

		for (i in 1...Std.int(getSectionBeats()))
		{
			var bs:FlxSprite = new FlxSprite(gridBG.x, (GRID_SIZE * (4 * zoomList[curZoom])) * i).makeGraphic(1, 1, 0x55FF4444);
			bs.scale.x = gridBG.width; bs.updateHitbox();
			if (vortex) gridLayer.add(bs);
		}

		var gbl2:FlxSprite = new FlxSprite(gridBG.x + GRID_SIZE).makeGraphic(1, 1, FlxColor.BLACK);
		gbl2.setGraphicSize(2, leHeight); gbl2.updateHitbox(); gbl2.antialiasing = false;
		gridLayer.add(gbl2);

		updateGrid();
		lastSecBeats     = getSectionBeats();
		lastSecBeatsNext = sectionStartTime(1) > FlxG.sound.music.length ? 0 : getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY():Void
	{
		strumLine.y = getYfromStrum((Conductor.songPosition - sectionStartTime()) / zoomList[curZoom] % (Conductor.stepCrochet * 16)) / (getSectionBeats() / 4);
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];
	var lastWaveformHeight:Int = 0;

	function updateWaveform():Void
	{
		#if (desktop || mobile)
		if (waveformPrinted)
		{
			var w:Int = Std.int(GRID_SIZE * 8); var h:Int = Std.int(gridBG.height);
			if (lastWaveformHeight != h && waveformSprite.pixels != null) { waveformSprite.pixels.dispose(); waveformSprite.pixels.disposeImage(); waveformSprite.makeGraphic(w, h, 0x00FFFFFF); lastWaveformHeight = h; }
			waveformSprite.pixels.fillRect(new Rectangle(0, 0, w, h), 0x00FFFFFF);
		}
		waveformPrinted = false;
		if (!FlxG.save.data.chart_waveformInst && !FlxG.save.data.chart_waveformVoices && !FlxG.save.data.chart_waveformOppVoices) return;
		wavData[0][0] = []; wavData[0][1] = []; wavData[1][0] = []; wavData[1][1] = [];
		var steps:Int = Math.round(getSectionBeats() * 4); var st:Float = sectionStartTime(); var et:Float = st + (Conductor.stepCrochet * steps);
		var sound:FlxSound = FlxG.sound.music;
		if (FlxG.save.data.chart_waveformVoices)    sound = vocals;
		else if (FlxG.save.data.chart_waveformOppVoices) sound = opponentVocals;
		if (sound != null && sound._sound != null && sound._sound.__buffer != null)
			wavData = waveformData(sound._sound.__buffer, sound._sound.__buffer.data.toBytes(), st, et, 1, wavData, Std.int(gridBG.height));
		var gSize:Int = Std.int(GRID_SIZE * 8); var hSize:Int = Std.int(gSize / 2);
		var length:Int = Std.int(Math.max(Std.int(Math.max(wavData[0][0].length, wavData[0][1].length)), Std.int(Math.max(wavData[1][0].length, wavData[1][1].length))));
		for (index in 0...length)
		{
			var lmin:Float = FlxMath.bound(((index < wavData[0][0].length) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var lmax:Float = FlxMath.bound(((index < wavData[0][1].length) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var rmin:Float = FlxMath.bound(((index < wavData[1][0].length) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var rmax:Float = FlxMath.bound(((index < wavData[1][1].length) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), index, (lmin + rmin) + (lmax + rmax), 1), FlxColor.BLUE);
		}
		waveformPrinted = true;
		#end
	}

	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>, ?steps:Float):Array<Array<Array<Float>>>
	{
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null) return [[[0], [0]], [[0], [0]]];
		var khz:Float = buffer.sampleRate / 1000; var channels:Int = buffer.channels; var index:Int = Std.int(time * khz);
		var samples:Float = (endTime - time) * khz; if (steps == null) steps = 1280;
		var spr:Float = samples / steps; var sprI:Int = Std.int(spr);
		var gotIndex:Int = 0; var lmin:Float = 0; var lmax:Float = 0; var rmin:Float = 0; var rmax:Float = 0; var rows:Float = 0;
		if (array == null) array = [[[0], [0]], [[0], [0]]];
		while (index < (bytes.length - 1))
		{
			if (index >= 0)
			{
				var byte:Int = bytes.getUInt16(index * channels * 2); if (byte > 65535 / 2) byte -= 65535; var sample:Float = byte / 65535;
				if (sample > 0) { if (sample > lmax) lmax = sample; } else if (sample < 0) { if (sample < lmin) lmin = sample; }
				if (channels >= 2)
				{
					byte = bytes.getUInt16((index * channels * 2) + 2); if (byte > 65535 / 2) byte -= 65535; sample = byte / 65535;
					if (sample > 0) { if (sample > rmax) rmax = sample; } else if (sample < 0) { if (sample < rmin) rmin = sample; }
				}
			}
			var v1:Bool = sprI > 0 ? (index % sprI == 0) : false;
			while (v1 ? v1 : rows >= spr)
			{
				v1 = false; rows -= spr; gotIndex++;
				var lRMin:Float = Math.abs(lmin) * multiply; var lRMax:Float = lmax * multiply; var rRMin:Float = Math.abs(rmin) * multiply; var rRMax:Float = rmax * multiply;
				if (gotIndex > array[0][0].length) array[0][0].push(lRMin); else array[0][0][gotIndex - 1] += lRMin;
				if (gotIndex > array[0][1].length) array[0][1].push(lRMax); else array[0][1][gotIndex - 1] += lRMax;
				if (channels >= 2) { if (gotIndex > array[1][0].length) array[1][0].push(rRMin); else array[1][0][gotIndex - 1] += rRMin; if (gotIndex > array[1][1].length) array[1][1].push(rRMax); else array[1][1][gotIndex - 1] += rRMax; }
				else { if (gotIndex > array[1][0].length) array[1][0].push(lRMin); else array[1][0][gotIndex - 1] += lRMin; if (gotIndex > array[1][1].length) array[1][1].push(lRMax); else array[1][1][gotIndex - 1] += lRMax; }
				lmin = 0; lmax = 0; rmin = 0; rmax = 0;
			}
			index++; rows++;
			if (gotIndex > steps) break;
		}
		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}

	function changeNoteSustain(value:Float):Void
	{
		if (curSelectedNote != null && curSelectedNote[2] != null) { curSelectedNote[2] = Math.max(curSelectedNote[2] + Math.ceil(value), 0); updateNoteUI(); updateGrid(); }
	}

	function recalculateSteps(add:Float = 0):Int
	{
		var lc:BPMChangeEvent = {stepTime: 0, songTime: 0, bpm: 0};
		for (i in 0...Conductor.bpmChangeMap.length) if (FlxG.sound.music.time > Conductor.bpmChangeMap[i].songTime) lc = Conductor.bpmChangeMap[i];
		curStep = lc.stepTime + Math.floor((FlxG.sound.music.time - lc.songTime + add) / Conductor.stepCrochet);
		updateBeat();
		return curStep;
	}

	function resetSection(songBeginning:Bool = false):Void
	{
		updateGrid(); FlxG.sound.music.pause();
		FlxG.sound.music.time = sectionStartTime();
		if (songBeginning) { FlxG.sound.music.time = 0; curSec = 0; }
		pauseAndSetVocalsTime(); updateCurStep(); updateGrid(); updateSectionUI(); updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		var waveformChanged:Bool = false;
		if (_song.notes[sec] != null)
		{
			curSec = sec;
			if (updateMusic) { FlxG.sound.music.pause(); FlxG.sound.music.time = sectionStartTime(); pauseAndSetVocalsTime(); updateCurStep(); }
			var b1:Float = getSectionBeats(); var b2:Float = sectionStartTime(1) > FlxG.sound.music.length ? 0 : getSectionBeats(curSec + 1);
			if (b1 != lastSecBeats || b2 != lastSecBeatsNext) { reloadGridLayer(); waveformChanged = true; }
			else updateGrid();
			updateSectionUI();
		}
		else changeSection();
		Conductor.songPosition = FlxG.sound.music.time;
		if (!waveformChanged) updateWaveform();
		_updateSectionLabel();
	}

	function updateSectionUI():Void
	{
		var sec = _song.notes[curSec];
		stepperBeats.value           = getSectionBeats();
		check_mustHitSection.checked = sec.mustHitSection;
		check_gfSection.checked      = sec.gfSection;
		check_altAnim.checked        = sec.altAnim;
		check_changeBPM.checked      = sec.changeBPM;
		stepperSectionBPM.value      = sec.bpm;
		updateHeads();
	}

	var characterData:Dynamic = {iconP1: null, iconP2: null, vocalsP1: null, vocalsP2: null};

	function updateJsonData():Void
	{
		for (i in 1...3)
		{
			var data:CharacterFile = loadCharacterFile(Reflect.field(_song, 'player$i'));
			Reflect.setField(characterData, 'iconP$i', !characterFailed ? data.healthicon : 'face');
			Reflect.setField(characterData, 'vocalsP$i', data.vocals_file != null ? data.vocals_file : '');
		}
	}

	function updateHeads():Void
	{
		if (_song.notes[curSec].mustHitSection) { leftIcon.changeIcon(characterData.iconP1); rightIcon.changeIcon(characterData.iconP2); if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf'); }
		else { leftIcon.changeIcon(characterData.iconP2); rightIcon.changeIcon(characterData.iconP1); if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf'); }
	}

	var characterFailed:Bool = false;
	function loadCharacterFile(char:String):CharacterFile
	{
		characterFailed = false;
		var cp:String = 'characters/' + char + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(cp);
		if (!FileSystem.exists(path)) path = Paths.getSharedPath(cp);
		if (!FileSystem.exists(path))
		#else
		var path:String = Paths.getSharedPath(cp);
		if (!OpenFlAssets.exists(path))
		#end
		{ path = Paths.getSharedPath('characters/' + Character.DEFAULT_CHARACTER + '.json'); characterFailed = true; }
		#if MODS_ALLOWED
		return cast Json.parse(File.getContent(path));
		#else
		return cast Json.parse(OpenFlAssets.getText(path));
		#end
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null)
		{
			if (curSelectedNote[2] != null)
			{
				stepperSusLength.value = curSelectedNote[2];
				if (curSelectedNote[3] != null)
				{
					currentType = curNoteTypes.indexOf(curSelectedNote[3]);
					noteTypeDropDown.selectedLabel = currentType <= 0 ? '' : currentType + '. ' + curSelectedNote[3];
				}
			}
			else
			{
				eventDropDown.selectedLabel = curSelectedNote[1][curEventSelected][0];
				var sel:Int = Std.parseInt(eventDropDown.selectedId);
				if (sel > 0 && sel < eventStuff.length) descText.text = eventStuff[sel][1];
				value1InputText.text = curSelectedNote[1][curEventSelected][1];
				value2InputText.text = curSelectedNote[1][curEventSelected][2];
			}
			strumTimeInputText.text = '' + curSelectedNote[0];
		}
	}

	function updateGrid():Void
	{
		curRenderedNotes.forEachAlive(function(s:Note) s.destroy()); curRenderedNotes.clear();
		curRenderedSustains.forEachAlive(function(s:FlxSprite) s.destroy()); curRenderedSustains.clear();
		curRenderedNoteType.forEachAlive(function(s:FlxText) s.destroy()); curRenderedNoteType.clear();
		nextRenderedNotes.forEachAlive(function(s:Note) s.destroy()); nextRenderedNotes.clear();
		nextRenderedSustains.forEachAlive(function(s:FlxSprite) s.destroy()); nextRenderedSustains.clear();

		if (_song.notes[curSec].changeBPM && _song.notes[curSec].bpm > 0) Conductor.bpm = _song.notes[curSec].bpm;
		else { var db:Float = _song.bpm; for (i in 0...curSec) if (_song.notes[i].changeBPM) db = _song.notes[i].bpm; Conductor.bpm = db; }

		var beats:Float = getSectionBeats();
		for (i in _song.notes[curSec].sectionNotes)
		{
			var note:Note = setupNoteData(i, false);
			curRenderedNotes.add(note);
			if (note.sustainLength > 0) curRenderedSustains.add(setupSusNote(note, beats));
			if (i[3] != null && note.noteType != null && note.noteType.length > 0)
			{
				var ti:Int = curNoteTypes.indexOf(i[3]);
				var dt:AttachedFlxText = new AttachedFlxText(0, 0, 100, ti < 0 ? '?' : '' + ti, 24);
				dt.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				dt.xAdd = -32; dt.yAdd = 6; dt.borderSize = 1; curRenderedNoteType.add(dt); dt.sprTracker = note;
			}
			note.mustPress = _song.notes[curSec].mustHitSection;
			if (i[1] > 3) note.mustPress = !note.mustPress;
		}

		var st:Float = sectionStartTime(); var et:Float = sectionStartTime(1);
		for (i in _song.events)
			if (et > i[0] && i[0] >= st)
			{
				var note:Note = setupNoteData(i, false); curRenderedNotes.add(note);
				var evtxt:String = note.eventLength > 1 ? note.eventLength + ' Events:\n' + note.eventName : 'Event: ' + note.eventName + ' (' + Math.floor(note.strumTime) + 'ms)\nV1: ' + note.eventVal1 + ' V2: ' + note.eventVal2;
				var dt:AttachedFlxText = new AttachedFlxText(0, 0, 400, evtxt, 12);
				dt.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				dt.xAdd = -410; dt.borderSize = 1; if (note.eventLength > 1) dt.yAdd += 8; curRenderedNoteType.add(dt); dt.sprTracker = note;
			}

		var beatsNext:Float = getSectionBeats(1);
		if (curSec < _song.notes.length - 1)
			for (i in _song.notes[curSec + 1].sectionNotes)
			{
				var note:Note = setupNoteData(i, true); note.alpha = 0.6; nextRenderedNotes.add(note);
				if (note.sustainLength > 0) nextRenderedSustains.add(setupSusNote(note, beatsNext));
			}

		var stn:Float = sectionStartTime(1); var etn:Float = sectionStartTime(2);
		for (i in _song.events) if (etn > i[0] && i[0] >= stn) { var note:Note = setupNoteData(i, true); note.alpha = 0.6; nextRenderedNotes.add(note); }

		_updateSectionLabel();
	}

	function setupNoteData(i:Array<Dynamic>, isNextSection:Bool):Note
	{
		var daNoteInfo = i[1]; var daStrumTime = i[0]; var daSus:Dynamic = i[2];
		var note:Note = new Note(daStrumTime, daNoteInfo % 4, null, null, true);
		if (daSus != null)
		{
			if (!Std.isOfType(i[3], String)) i[3] = curNoteTypes[i[3]];
			if (i.length > 3 && (i[3] == null || i[3].length < 1)) i.remove(i[3]);
			note.sustainLength = daSus; note.noteType = i[3];
		}
		else
		{
			note.loadGraphic(Paths.image('eventArrow')); note.rgbShader.enabled = false;
			note.eventName = getEventName(i[1]); note.eventLength = i[1].length;
			if (i[1].length < 2) { note.eventVal1 = i[1][0][1]; note.eventVal2 = i[1][0][2]; }
			note.noteData = -1; daNoteInfo = -1;
		}
		note.setGraphicSize(GRID_SIZE, GRID_SIZE); note.updateHitbox();
		note.x = Math.floor(daNoteInfo * GRID_SIZE) + GRID_SIZE;
		if (isNextSection && _song.notes[curSec].mustHitSection != _song.notes[curSec + 1].mustHitSection)
		{
			if (daNoteInfo > 3) note.x -= GRID_SIZE * 4;
			else if (daSus != null) note.x += GRID_SIZE * 4;
		}
		var bl:Float = getSectionBeats(isNextSection ? 1 : 0);
		note.y = getYfromStrumNotes(daStrumTime - sectionStartTime(), bl);
		if (isNextSection) note.y += gridBG.height;
		if (note.y < -150) note.y = -150;
		return note;
	}

	function getEventName(names:Array<Dynamic>):String
	{
		var r:String = ''; var added:Bool = false;
		for (i in 0...names.length) { if (added) r += ', '; r += names[i][0]; added = true; }
		return r;
	}

	function setupSusNote(note:Note, beats:Float):FlxSprite
	{
		var height:Int = Math.floor(FlxMath.remapToRange(note.sustainLength, 0, Conductor.stepCrochet * 16, 0, GRID_SIZE * 16 * zoomList[curZoom]) + (GRID_SIZE * zoomList[curZoom]) - GRID_SIZE / 2);
		var minH:Int   = Std.int((GRID_SIZE * zoomList[curZoom] / 2) + GRID_SIZE / 2);
		if (height < minH) height = minH; if (height < 1) height = 1;
		var spr:FlxSprite = new FlxSprite(note.x + (GRID_SIZE * 0.5) - 4, note.y + GRID_SIZE / 2).makeGraphic(8, height);
		spr.color = 0xFFAAAAAA;
		return spr;
	}

	private function addSection(sectionBeats:Float = 4):Void
	{
		_song.notes.push({sectionBeats: sectionBeats, bpm: _song.bpm, changeBPM: false, mustHitSection: true, gfSection: false, sectionNotes: [], altAnim: false});
	}

	function selectNote(note:Note):Void
	{
		var ndc:Int = note.noteData;
		if (ndc > -1)
		{
			if (note.mustPress != _song.notes[curSec].mustHitSection) ndc += 4;
			for (i in _song.notes[curSec].sectionNotes) if (i != curSelectedNote && i.length > 2 && i[0] == note.strumTime && i[1] == ndc) { curSelectedNote = i; break; }
		}
		else for (i in _song.events) if (i != curSelectedNote && i[0] == note.strumTime) { curSelectedNote = i; curEventSelected = Std.int(curSelectedNote[1].length) - 1; break; }
		changeEventSelected(); updateGrid(); updateNoteUI();
		_setStatus('Note selected at ${Math.round(curSelectedNote[0])}ms', 0xFFFFCC00);
	}

	function deleteNote(note:Note):Void
	{
		var ndc:Int = note.noteData;
		if (ndc > -1 && note.mustPress != _song.notes[curSec].mustHitSection) ndc += 4;
		if (note.noteData > -1)
		{
			for (i in _song.notes[curSec].sectionNotes) if (i[0] == note.strumTime && i[1] == ndc) { if (i == curSelectedNote) curSelectedNote = null; _song.notes[curSec].sectionNotes.remove(i); _spawnNoteFeedback(note.x, note.y, true); break; }
		}
		else for (i in _song.events) if (i[0] == note.strumTime) { if (i == curSelectedNote) { curSelectedNote = null; changeEventSelected(); } _song.events.remove(i); break; }
		updateGrid();
	}

	public function doANoteThing(cs:Float, d:Int, style:Int):Void
	{
		var dn:Bool = false;
		if (strumLineNotes.members[d].overlaps(curRenderedNotes))
			curRenderedNotes.forEachAlive(function(note:Note) { if (note.overlapsPoint(new FlxPoint(strumLineNotes.members[d].x + 1, strumLine.y + 1)) && note.noteData == d % 4) { if (!dn) { deleteNote(note); dn = true; } } });
		if (!dn) addNote(cs, d, style);
	}

	function clearSong():Void
	{
		for (s in 0..._song.notes.length) _song.notes[s].sectionNotes = [];
		updateGrid();
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null):Void
	{
		var noteStrum:Float = getStrumTime(dummyArrow.y * (getSectionBeats() / 4), false) + sectionStartTime();
		var noteData:Int    = 0;
		if (controls.mobileC) for (touch in FlxG.touches.list) noteData = Math.floor((touch.x - GRID_SIZE) / GRID_SIZE);
		else noteData = Math.floor((FlxG.mouse.x - GRID_SIZE) / GRID_SIZE);
		var daType:Int = currentType;
		if (strum != null) noteStrum = strum; if (data != null) noteData = data; if (type != null) daType = type;
		if (noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, noteData, 0, curNoteTypes[daType]]);
			curSelectedNote = _song.notes[curSec].sectionNotes[_song.notes[curSec].sectionNotes.length - 1];
			_spawnNoteFeedback(Math.floor(noteData * GRID_SIZE) + GRID_SIZE, dummyArrow.y, false);
		}
		else
		{
			_song.events.push([noteStrum, [[eventStuff[Std.parseInt(eventDropDown.selectedId)][0], value1InputText.text, value2InputText.text]]]);
			curSelectedNote = _song.events[_song.events.length - 1]; curEventSelected = 0;
		}
		changeEventSelected();
		if (FlxG.keys.pressed.CONTROL && noteData > -1) _song.notes[curSec].sectionNotes.push([noteStrum, (noteData + 4) % 8, 0, curNoteTypes[daType]]);
		strumTimeInputText.text = '' + curSelectedNote[0]; updateGrid(); updateNoteUI();
	}

	function redo():Void {}
	function undo():Void { if (undos.length > 0) { undos.pop(); _setStatus('Undo (${undos.length} left)', 0xFFFFCC00); } }

	function getStrumTime(yPos:Float, doZoomCalc:Bool = true):Float
	{
		var lz:Float = doZoomCalc ? zoomList[curZoom] : 1;
		return FlxMath.remapToRange(yPos, gridBG.y, gridBG.y + gridBG.height * lz, 0, 16 * Conductor.stepCrochet);
	}

	function getYfromStrum(strumTime:Float, doZoomCalc:Bool = true):Float
	{
		var lz:Float = doZoomCalc ? zoomList[curZoom] : 1;
		return FlxMath.remapToRange(strumTime, 0, 16 * Conductor.stepCrochet, gridBG.y, gridBG.y + gridBG.height * lz);
	}

	function getYfromStrumNotes(strumTime:Float, beats:Float):Float
	{
		return GRID_SIZE * beats * 4 * zoomList[curZoom] * (strumTime / (beats * 4 * Conductor.stepCrochet)) + gridBG.y;
	}

	function getNotes():Array<Dynamic>
	{
		var nd:Array<Dynamic> = [];
		for (i in _song.notes) nd.push(i.sectionNotes);
		return nd;
	}

	var missingText:FlxText;
	var missingTextTimer:FlxTimer;

	function loadJson(song:String):Void
	{
		try
		{
			if (Difficulty.getString() != Difficulty.getDefault() && Difficulty.getString() != null)
				PlayState.SONG = Song.loadFromJson(song.toLowerCase() + "-" + Difficulty.getString(), song.toLowerCase());
			else
				PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
			MusicBeatState.resetState();
		}
		catch (e)
		{
			var es:String = e.toString();
			if (es.startsWith('[file_contents,assets/data/')) es = 'Missing file: ' + es.substring(27, es.length - 1);
			if (missingText == null)
			{
				missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
				missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				missingText.scrollFactor.set(); add(missingText);
			}
			else missingTextTimer.cancel();
			missingText.text = 'ERROR LOADING CHART:\n$es';
			missingText.screenCenter(Y);
			missingTextTimer = new FlxTimer().start(5, function(_:FlxTimer) { remove(missingText); missingText.destroy(); });
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	function autosaveSong():Void
	{
		FlxG.save.data.autosave = haxe.Json.stringify({"song": _song});
		FlxG.save.flush();
	}

	function clearEvents():Void { _song.events = []; updateGrid(); }

	private function saveLevel():Void
	{
		if (_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var data:String = haxe.Json.stringify({"song": _song}, "\t");
		if (data != null && data.length > 0)
		{
			#if mobile
			StorageUtil.saveContent('${Paths.formatToSongPath(_song.song)}.json', data.trim());
			_setStatus('Chart saved!', 0xFFAAFFAA);
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), Paths.formatToSongPath(_song.song) + ".json");
			#end
		}
	}

	function sortByTime(O1:Array<Dynamic>, O2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, O1[0], O2[0]);
	}

	private function saveEventsToFile():Void
	{
		if (_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var data:String = haxe.Json.stringify({"song": {events: _song.events}}, "\t");
		if (data != null && data.length > 0)
		{
			#if mobile
			StorageUtil.saveContent("events.json", data.trim());
			_setStatus('Events saved!', 0xFFAAFFAA);
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events.json");
			#end
		}
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_setStatus('Saved!', 0xFFAAFFAA);
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_setStatus('Error saving!', FlxColor.RED);
	}

	function getSectionBeats(?section:Null<Int> = null):Float
	{
		if (section == null) section = curSec;
		var val:Null<Float> = _song.notes[section] != null ? _song.notes[section].sectionBeats : null;
		return val != null ? val : 4;
	}
}

class AttachedFlxText extends FlxText
{
	public var sprTracker:FlxSprite;
	public var xAdd:Float = 0;
	public var yAdd:Float = 0;

	public function new(X:Float = 0, Y:Float = 0, FieldWidth:Float = 0, ?Text:String, Size:Int = 8, EmbeddedFont:Bool = true)
	{
		super(X, Y, FieldWidth, Text, Size, EmbeddedFont);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (sprTracker != null) { setPosition(sprTracker.x + xAdd, sprTracker.y + yAdd); angle = sprTracker.angle; alpha = sprTracker.alpha; }
	}
}
