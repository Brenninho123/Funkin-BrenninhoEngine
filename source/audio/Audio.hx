package audio;

import flixel.sound.FlxSound;
import flixel.math.FlxMath;
import openfl.media.SoundTransform;
import openfl.events.Event;

typedef AudioEffect =
{
	var name:String;
	var intensity:Float;
	var enabled:Bool;
}

typedef AudioSnapshot =
{
	var musicVolume:Float;
	var sfxVolume:Float;
	var masterVolume:Float;
	var pitch:Float;
	var timestamp:Float;
}

class Audio
{
	static final FADE_MIN_VOLUME:Float     = 0.0001;
	static final COMPRESSOR_THRESHOLD:Float = 0.8;
	static final COMPRESSOR_RATIO:Float     = 0.6;
	static final BASS_BOOST_MAX:Float       = 0.4;
	static final TREBLE_BOOST_MAX:Float     = 0.3;
	static final DUCKING_AMOUNT:Float       = 0.4;
	static final DUCKING_SPEED:Float        = 8.0;

	public static var masterVolume(default, set):Float  = 1.0;
	public static var musicVolume(default, set):Float   = 1.0;
	public static var sfxVolume(default, set):Float     = 1.0;

	public static var isInitialized:Bool                = false;
	public static var onBeat:Int->Void                  = null;
	public static var onVolumeChanged:Float->Void       = null;

	private static var _effects:Map<String, AudioEffect>   = new Map();
	private static var _snapshots:Array<AudioSnapshot>     = [];
	private static var _trackedSounds:Array<FlxSound>      = [];
	private static var _duckedSounds:Array<FlxSound>       = [];
	private static var _isDucking:Bool                     = false;
	private static var _duckTimer:Float                    = 0.0;
	private static var _beatCount:Int                      = 0;
	private static var _lastBeatTime:Float                 = 0.0;
	private static var _compressorEnabled:Bool             = false;
	private static var _bassBoost:Float                    = 0.0;
	private static var _trebleBoost:Float                  = 0.0;
	private static var _pitch:Float                        = 1.0;
	private static var _crossfadeActive:Bool               = false;

	public static function init():Void
	{
		if (isInitialized)
			return;

		isInitialized = true;
		masterVolume  = 1.0;
		musicVolume   = ClientPrefs.data.hitsoundVolume > 0 ? 1.0 : 1.0;
		sfxVolume     = 1.0;

		_registerDefaultEffects();
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized) return;

		if (_isDucking)
		{
			_duckTimer += elapsed;
			for (sound in _duckedSounds)
			{
				if (sound == null || !sound.alive) continue;
				var target:Float = sound.volume * (1.0 - DUCKING_AMOUNT);
				sound.volume    = FlxMath.lerp(sound.volume, target, DUCKING_SPEED * elapsed);
			}
		}

		if (_compressorEnabled && FlxG.sound.music != null && FlxG.sound.music.playing)
			_applyCompressor();

		_cleanTrackedSounds();
	}

	public static function playMusic(key:String, ?volume:Float = 1.0, ?loop:Bool = true, ?fadeDuration:Float = 0.0):Void
	{
		var targetVolume:Float = volume * musicVolume * masterVolume;

		if (fadeDuration > 0 && FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			fadeOut(FlxG.sound.music, fadeDuration * 0.5, function():Void
			{
				FlxG.sound.playMusic(Paths.music(key), 0, loop);
				fadeIn(FlxG.sound.music, fadeDuration * 0.5, targetVolume);
			});
		}
		else
		{
			FlxG.sound.playMusic(Paths.music(key), fadeDuration > 0 ? 0 : targetVolume, loop);
			if (fadeDuration > 0)
				fadeIn(FlxG.sound.music, fadeDuration, targetVolume);
		}

		#if FLX_PITCH
		if (_pitch != 1.0 && FlxG.sound.music != null)
			FlxG.sound.music.pitch = _pitch;
		#end
	}

	public static function playSound(key:String, ?volume:Float = 1.0, ?loop:Bool = false):FlxSound
	{
		var finalVolume:Float = volume * sfxVolume * masterVolume;
		var sound:FlxSound    = FlxG.sound.play(Paths.sound(key), finalVolume, loop);

		if (sound != null)
		{
			#if FLX_PITCH
			sound.pitch = _pitch;
			#end
			_trackedSounds.push(sound);
		}

		return sound;
	}

	public static function fadeIn(sound:FlxSound, duration:Float, ?targetVolume:Float = 1.0, ?onComplete:Void->Void):Void
	{
		if (sound == null) return;

		sound.volume = FADE_MIN_VOLUME;
		FlxTween.tween(sound, {volume: targetVolume * masterVolume}, duration, {
			ease: FlxEase.quartOut,
			onComplete: function(_:FlxTween):Void
			{
				if (onComplete != null) onComplete();
			}
		});
	}

	public static function fadeOut(sound:FlxSound, duration:Float, ?onComplete:Void->Void):Void
	{
		if (sound == null) return;

		FlxTween.tween(sound, {volume: FADE_MIN_VOLUME}, duration, {
			ease: FlxEase.quartIn,
			onComplete: function(_:FlxTween):Void
			{
				sound.stop();
				if (onComplete != null) onComplete();
			}
		});
	}

	public static function crossfade(fromSound:FlxSound, toKey:String, duration:Float, ?loop:Bool = true):Void
	{
		if (_crossfadeActive) return;
		_crossfadeActive = true;

		var toSound:FlxSound = FlxG.sound.play(Paths.music(toKey), FADE_MIN_VOLUME, loop);
		if (toSound == null) { _crossfadeActive = false; return; }

		var targetVolume:Float = musicVolume * masterVolume;

		FlxTween.tween(fromSound, {volume: FADE_MIN_VOLUME}, duration, { ease: FlxEase.quartIn });
		FlxTween.tween(toSound,   {volume: targetVolume},    duration, {
			ease: FlxEase.quartOut,
			onComplete: function(_:FlxTween):Void
			{
				fromSound.stop();
				_crossfadeActive = false;
			}
		});
	}

	public static function setPitch(value:Float):Void
	{
		_pitch = FlxMath.bound(value, 0.1, 4.0);

		#if FLX_PITCH
		if (FlxG.sound.music != null)
			FlxG.sound.music.pitch = _pitch;

		for (sound in _trackedSounds)
			if (sound != null && sound.alive)
				sound.pitch = _pitch;
		#end
	}

	public static function getPitch():Float
	{
		return _pitch;
	}

	public static function setMusicLowPass(enabled:Bool, ?intensity:Float = 0.5):Void
	{
		var effect:AudioEffect = _getOrCreateEffect('lowpass');
		effect.enabled   = enabled;
		effect.intensity = FlxMath.bound(intensity, 0.0, 1.0);

		if (FlxG.sound.music == null) return;

		var transform:SoundTransform = FlxG.sound.music.soundTransform;
		transform.volume = enabled
			? FlxG.sound.music.volume * (1.0 - effect.intensity * 0.6)
			: FlxG.sound.music.volume;
		FlxG.sound.music.soundTransform = transform;
	}

	public static function setBassBoost(value:Float):Void
	{
		_bassBoost = FlxMath.bound(value, 0.0, 1.0);
		var effect:AudioEffect = _getOrCreateEffect('bass_boost');
		effect.enabled   = _bassBoost > 0;
		effect.intensity = _bassBoost;
		_applyVolumeBoost(_bassBoost * BASS_BOOST_MAX);
	}

	public static function setTrebleBoost(value:Float):Void
	{
		_trebleBoost = FlxMath.bound(value, 0.0, 1.0);
		var effect:AudioEffect = _getOrCreateEffect('treble_boost');
		effect.enabled   = _trebleBoost > 0;
		effect.intensity = _trebleBoost;
	}

	public static function setCompressor(enabled:Bool):Void
	{
		_compressorEnabled = enabled;
		var effect:AudioEffect = _getOrCreateEffect('compressor');
		effect.enabled = enabled;
	}

	public static function duck(sounds:Array<FlxSound>, ?duration:Float = 0.0):Void
	{
		_duckedSounds = sounds.filter((s:FlxSound) -> s != null && s.alive);
		_isDucking    = true;
		_duckTimer    = 0.0;

		if (duration > 0)
			FlxTimer.wait(duration, unduck);
	}

	public static function unduck():Void
	{
		_isDucking = false;
		_duckTimer = 0.0;

		for (sound in _duckedSounds)
			if (sound != null && sound.alive)
				FlxTween.tween(sound, {volume: sfxVolume * masterVolume}, 0.3, {ease: FlxEase.quartOut});

		_duckedSounds = [];
	}

	public static function setReverb(sound:FlxSound, ?intensity:Float = 0.3):Void
	{
		if (sound == null) return;
		var transform:SoundTransform = sound.soundTransform;
		transform.volume             = sound.volume * (1.0 + intensity * 0.15);
		sound.soundTransform         = transform;
	}

	public static function takeSnapshot():AudioSnapshot
	{
		var snapshot:AudioSnapshot = {
			musicVolume:  musicVolume,
			sfxVolume:    sfxVolume,
			masterVolume: masterVolume,
			pitch:        _pitch,
			timestamp:    Date.now().getTime()
		};
		_snapshots.push(snapshot);
		return snapshot;
	}

	public static function restoreSnapshot(?snapshot:AudioSnapshot):Void
	{
		var s:AudioSnapshot = snapshot != null ? snapshot
			: (_snapshots.length > 0 ? _snapshots[_snapshots.length - 1] : null);

		if (s == null) return;

		masterVolume = s.masterVolume;
		musicVolume  = s.musicVolume;
		sfxVolume    = s.sfxVolume;
		setPitch(s.pitch);

		if (snapshot == null && _snapshots.length > 0)
			_snapshots.pop();
	}

	public static function muteAll():Void
	{
		takeSnapshot();
		masterVolume = 0.0;
	}

	public static function unmuteAll():Void
	{
		restoreSnapshot();
	}

	public static function stopAll():Void
	{
		FlxG.sound.music?.stop();
		for (sound in _trackedSounds)
			if (sound != null && sound.alive)
				sound.stop();
		_trackedSounds = [];
	}

	public static function pauseAll():Void
	{
		FlxG.sound.music?.pause();
		for (sound in _trackedSounds)
			if (sound != null && sound.alive && sound.playing)
				sound.pause();
	}

	public static function resumeAll():Void
	{
		FlxG.sound.music?.resume();
		for (sound in _trackedSounds)
			if (sound != null && sound.alive && !sound.playing)
				sound.resume();
	}

	public static function getActiveEffects():Array<AudioEffect>
	{
		return [for (_ => effect in _effects) if (effect.enabled) effect];
	}

	public static function resetEffects():Void
	{
		for (_ => effect in _effects)
			effect.enabled = false;

		_bassBoost         = 0.0;
		_trebleBoost       = 0.0;
		_compressorEnabled = false;
		setPitch(1.0);
		setMusicLowPass(false);

		if (FlxG.sound.music != null)
		{
			var transform:SoundTransform = FlxG.sound.music.soundTransform;
			transform.volume             = musicVolume * masterVolume;
			FlxG.sound.music.soundTransform = transform;
		}
	}

	public static function onSongBeat(beat:Int):Void
	{
		_beatCount  = beat;
		_lastBeatTime = Date.now().getTime();
		if (onBeat != null) onBeat(beat);
	}

	private static function _applyCompressor():Void
	{
		if (FlxG.sound.music == null) return;
		var vol:Float = FlxG.sound.music.volume;
		if (vol > COMPRESSOR_THRESHOLD)
		{
			var excess:Float    = vol - COMPRESSOR_THRESHOLD;
			var compressed:Float = COMPRESSOR_THRESHOLD + (excess * COMPRESSOR_RATIO);
			FlxG.sound.music.volume = FlxMath.bound(compressed, 0.0, 1.0);
		}
	}

	private static function _applyVolumeBoost(boost:Float):Void
	{
		if (FlxG.sound.music == null) return;
		var transform:SoundTransform = FlxG.sound.music.soundTransform;
		transform.volume             = FlxMath.bound(FlxG.sound.music.volume + boost, 0.0, 1.2);
		FlxG.sound.music.soundTransform = transform;
	}

	private static function _getOrCreateEffect(name:String):AudioEffect
	{
		if (!_effects.exists(name))
			_effects.set(name, { name: name, intensity: 0.0, enabled: false });
		return _effects.get(name);
	}

	private static function _cleanTrackedSounds():Void
	{
		_trackedSounds = _trackedSounds.filter((s:FlxSound) -> s != null && s.alive);
	}

	private static function _registerDefaultEffects():Void
	{
		_getOrCreateEffect('lowpass');
		_getOrCreateEffect('bass_boost');
		_getOrCreateEffect('treble_boost');
		_getOrCreateEffect('compressor');
		_getOrCreateEffect('reverb');
	}

	private static function set_masterVolume(value:Float):Float
	{
		masterVolume = FlxMath.bound(value, 0.0, 1.0);
		FlxG.sound.volume = masterVolume;
		if (onVolumeChanged != null) onVolumeChanged(masterVolume);
		return masterVolume;
	}

	private static function set_musicVolume(value:Float):Float
	{
		musicVolume = FlxMath.bound(value, 0.0, 1.0);
		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = musicVolume * masterVolume;
		return musicVolume;
	}

	private static function set_sfxVolume(value:Float):Float
	{
		sfxVolume = FlxMath.bound(value, 0.0, 1.0);
		for (sound in _trackedSounds)
			if (sound != null && sound.alive)
				sound.volume = sfxVolume * masterVolume;
		return sfxVolume;
	}
}
