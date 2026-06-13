package shaders;

class ColorSwap
{
	public var shader(default, null):ColorSwapShader = new ColorSwapShader();

	public var hue(default, set):Float        = 0;
	public var saturation(default, set):Float = 0;
	public var brightness(default, set):Float = 0;
	public var contrast(default, set):Float   = 0;
	public var temperature(default, set):Float = 0;
	public var outline(default, set):Bool     = false;
	public var outlineColor(default, set):Array<Float> = [1.0, 1.0, 1.0, 1.0];
	public var outlineSize(default, set):Float = 3.0;
	public var vignette(default, set):Float   = 0.0;
	public var vignetteColor(default, set):Array<Float> = [0.0, 0.0, 0.0];

	private function set_hue(v:Float):Float
	{
		shader.uHSBC.value[0] = hue = v;
		return v;
	}
	private function set_saturation(v:Float):Float
	{
		shader.uHSBC.value[1] = saturation = v;
		return v;
	}
	private function set_brightness(v:Float):Float
	{
		shader.uHSBC.value[2] = brightness = v;
		return v;
	}
	private function set_contrast(v:Float):Float
	{
		shader.uHSBC.value[3] = contrast = v;
		return v;
	}
	private function set_temperature(v:Float):Float
	{
		shader.uTemperature.value[0] = temperature = v;
		return v;
	}
	private function set_outline(v:Bool):Bool
	{
		shader.awesomeOutline.value[0] = outline = v;
		return v;
	}
	private function set_outlineColor(v:Array<Float>):Array<Float>
	{
		shader.uOutlineColor.value = v;
		return outlineColor = v;
	}
	private function set_outlineSize(v:Float):Float
	{
		shader.uOutlineSize.value[0] = outlineSize = v;
		return v;
	}
	private function set_vignette(v:Float):Float
	{
		shader.uVignette.value[0] = vignette = v;
		return v;
	}
	private function set_vignetteColor(v:Array<Float>):Array<Float>
	{
		shader.uVignetteColor.value = v;
		return vignetteColor = v;
	}

	public function new()
	{
		shader.uHSBC.value          = [0.0, 0.0, 0.0, 0.0];
		shader.uTemperature.value   = [0.0];
		shader.awesomeOutline.value = [false];
		shader.uOutlineColor.value  = [1.0, 1.0, 1.0, 1.0];
		shader.uOutlineSize.value   = [3.0];
		shader.uVignette.value      = [0.0];
		shader.uVignetteColor.value = [0.0, 0.0, 0.0];
	}

	public function reset():Void
	{
		hue         = 0;
		saturation  = 0;
		brightness  = 0;
		contrast    = 0;
		temperature = 0;
		outline     = false;
		outlineSize = 3.0;
		outlineColor = [1.0, 1.0, 1.0, 1.0];
		vignette    = 0.0;
		vignetteColor = [0.0, 0.0, 0.0];
	}
}

class ColorSwapShader extends FlxShader
{
	@:glFragmentSource('
		#pragma header

		uniform vec4  uHSBC;
		uniform float uTemperature;
		uniform bool  awesomeOutline;
		uniform vec4  uOutlineColor;
		uniform float uOutlineSize;
		uniform float uVignette;
		uniform vec3  uVignetteColor;

		vec3 rgb2hsv(vec3 c)
		{
			vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
			vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
			float d = q.x - min(q.w, q.y);
			float e = 1.0e-10;
			return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
		}

		vec3 hsv2rgb(vec3 c)
		{
			vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
			vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
			return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		vec3 applyTemperature(vec3 color, float temp)
		{
			color.r += temp * 0.1;
			color.b -= temp * 0.1;
			return clamp(color, 0.0, 1.0);
		}

		vec3 applyContrast(vec3 color, float contrast)
		{
			return clamp((color - 0.5) * (1.0 + contrast) + 0.5, 0.0, 1.0);
		}

		float luminance(vec3 c)
		{
			return dot(c, vec3(0.2126, 0.7152, 0.0722));
		}

		vec3 softGamma(vec3 color)
		{
			return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
		}

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
			if (color.a == 0.0)
			{
				gl_FragColor = vec4(0.0);
				return;
			}

			vec3 rgb = color.rgb / color.a;

			// temperature
			if (uTemperature != 0.0)
				rgb = applyTemperature(rgb, uTemperature);

			// HSV
			vec3 hsv  = rgb2hsv(rgb);
			hsv.x     = fract(hsv.x + uHSBC.x);
			hsv.y     = clamp(hsv.y + uHSBC.y, 0.0, 1.0);
			hsv.z     = clamp(hsv.z * (1.0 + uHSBC.z), 0.0, 1.0);
			rgb       = hsv2rgb(hsv);

			// contrast
			if (uHSBC.w != 0.0)
				rgb = applyContrast(rgb, uHSBC.w);

			// soft gamma correction for relaxing look
			rgb = mix(rgb, softGamma(rgb), 0.35);

			// subtle desaturate dark areas (crushed blacks look harsh)
			float lum = luminance(rgb);
			rgb       = mix(rgb, vec3(lum), clamp((0.18 - lum) * 1.5, 0.0, 0.25));

			color     = vec4(rgb * color.a, color.a);

			// outline
			if (awesomeOutline && color.a <= 0.5)
			{
				float w = uOutlineSize / openfl_TextureSize.x;
				float h = uOutlineSize / openfl_TextureSize.y;
				float n = flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w,  0)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w,  0)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( 0,  h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( 0, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w,  h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w,  h)).a;
				if (n > 0.0)
					color = uOutlineColor;
			}

			// vignette
			if (uVignette > 0.0)
			{
				vec2  uv     = openfl_TextureCoordv * 2.0 - 1.0;
				float vd     = 1.0 - dot(uv * vec2(0.75, 1.0), uv * vec2(0.75, 1.0));
				float factor = smoothstep(0.0, 1.0, vd);
				factor       = mix(1.0, factor, uVignette);
				color.rgb    = mix(uVignetteColor * color.a, color.rgb, factor);
			}

			gl_FragColor = color;
		}')

	@:glVertexSource('
		#pragma header

		void main()
		{
			#pragma body
		}')

	public function new()
	{
		super();
	}
}
