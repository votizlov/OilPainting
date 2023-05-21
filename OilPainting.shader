// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Unlit/Oil Painting"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _Radius ("Radius", Range(0, 10)) = 0
        _BlurSize("Blur Size", Range(0, 0.1)) = 0
        _StandardDeviation("Standard Deviation", Range(0, 0.1)) = 0.02
        _VignetteIntensity("Vignette Intensity", Range(0, 1)) = 0.5
        _VignetteSmoothness("Vignette Smoothness", Range(0, 1)) = 0.2
        _NormalWeight ("Normal Weight", Range(0, 1)) = 0.5

        [Toggle(GAUSS)] _Gauss ("Gaussian Blur", float) = 0
    }
    SubShader
    {
        Blend SrcAlpha OneMinusSrcAlpha
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #define PI 3.14159265359
            #define E 2.71828182846
            #define SAMPLES 10
            float _BlurSize;
            float _StandardDeviation;
            float _VignetteIntensity;
            float _VignetteSmoothness;
            float _NormalWeight;

            struct v2f
            {
                float4 pos : SV_POSITION;
                half2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            sampler2D _NormalMap;
            float4 _MainTex_ST;


            float vignette(float2 uv, float intensity, float smoothness)
            {
                float2 position = uv - 0.5;
                float distance = length(position);
                float vignette = smoothstep(smoothness, smoothness - intensity, distance);
                return vignette;
            }

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                return o;
            }

            int _Radius;
            float4 _MainTex_TexelSize;

            float4 frag(v2f i) : SV_Target
            {
                float3 normal = UnpackNormal(tex2D(_NormalMap, i.uv));
                half2 uv = i.uv;

                float3 mean[4] = {
                    {0, 0, 0},
                    {0, 0, 0},
                    {0, 0, 0},
                    {0, 0, 0}
                };

                float3 sigma[4] = {
                    {0, 0, 0},
                    {0, 0, 0},
                    {0, 0, 0},
                    {0, 0, 0}
                };

                float2 start[4] = {{-_Radius, -_Radius}, {-_Radius, 0}, {0, -_Radius}, {0, 0}};

                float2 pos;
                float3 col;
                float normalInfluence;
                for (int k = 0; k < 4; k++)
                {
                    for (int i = 0; i <= _Radius; i++)
                    {
                        for (int j = 0; j <= _Radius; j++)
                        {
                            float2 kernelDirection = float2(i - 1, j - 1);
                            kernelDirection = normalize(kernelDirection);
                            normalInfluence = dot(normal, kernelDirection);
                            //float weightedVariance = variance + normalInfluence * _NormalWeight;
                            pos = float2(i, j) + start[k];
                            col = tex2Dlod(_MainTex, float4(
                                               uv + float2(pos.x * _MainTex_TexelSize.x, pos.y * _MainTex_TexelSize.y),
                                               0., 0.)).rgb;
                            mean[k] += col;
                            sigma[k] += col * col; //+ normalInfluence * _NormalWeight;
                        }
                    }
                }

                float sigma2;

                float n = pow(_Radius + 1, 2);
                float4 color = tex2D(_MainTex, uv);
                float min = 1;

                for (int l = 0; l < 4; l++)
                {
                    mean[l] /= n;
                    sigma[l] = abs(sigma[l] / n - mean[l] * mean[l]);
                    sigma2 = sigma[l].r + sigma[l].g + sigma[l].b;

                    if (sigma2 < min + normalInfluence * _NormalWeight)
                    {
                        min = sigma2;
                        color.rgb = mean[l].rgb;
                    }
                }
                // blur

                #if GAUSS
				//failsafe so we can use turn off the blur by setting the deviation to 0
				if(_StandardDeviation == 0)
				return tex2D(_MainTex, i.uv);
                #endif
                #if GAUSS
				float sum = 0;
                #else
                float sum = SAMPLES;
                #endif
                //iterate over blur samples
                for (float index = 0; index < SAMPLES; index++)
                {
                    //get the offset of the sample
                    float offset = (index / (SAMPLES - 1) - 0.5) * _BlurSize;
                    //get uv coordinate of sample
                    float2 uv = i.uv + float2(0, offset);
                    #if !GAUSS
                    //simply add the color if we don't have a gaussian blur (box)
                    col += tex2D(_MainTex, uv);
                    #else
					//calculate the result of the gaussian function
					float stDevSquared = _StandardDeviation*_StandardDeviation;
					float gauss = (1 / sqrt(2*PI*stDevSquared)) * pow(E, -((offset*offset)/(2*stDevSquared)));
					//add result to sum
					sum += gauss;
					//multiply color with influence from gaussian function and add it to sum color
					col += tex2D(_MainTex, uv) * gauss;
                    #endif
                }
                //divide the sum of values by the amount of samples
                color.rgb = col / sum * color.rgb;

                float vignetteEffect = vignette(i.uv, _VignetteIntensity, _VignetteSmoothness);
                color.rgb = color.rgb * vignetteEffect;

                return color;
            }
            ENDCG
        }
        /*
        //Horizontal Blur
		Pass{
			CGPROGRAM
			//include useful shader functions
			#include "UnityCG.cginc"

			#pragma multi_compile _SAMPLES_LOW _SAMPLES_MEDIUM _SAMPLES_HIGH
			#pragma shader_feature GAUSS

			//define vertex and fragment shader
			#pragma vertex vert
			#pragma fragment frag

			//texture and transforms of the texture
			sampler2D _MainTex;
			float _BlurSize;
			float _StandardDeviation;

			#define PI 3.14159265359
			#define E 2.71828182846

		#if _SAMPLES_LOW
			#define SAMPLES 10
		#elif _SAMPLES_MEDIUM
			#define SAMPLES 30
		#else
			#define SAMPLES 100
		#endif

			//the object data that's put into the vertex shader
			struct appdata{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			//the data that's used to generate fragments and can be read by the fragment shader
			struct v2f{
				float4 position : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			//the vertex shader
			v2f vert(appdata v){
				v2f o;
				//convert the vertex positions from object space to clip space so they can be rendered
				o.position = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			//the fragment shader
			fixed4 frag(v2f i) : SV_TARGET{
			#if GAUSS
				//failsafe so we can use turn off the blur by setting the deviation to 0
				if(_StandardDeviation == 0)
				return tex2D(_MainTex, i.uv);
			#endif
				//calculate aspect ratio
				float invAspect = _ScreenParams.y / _ScreenParams.x;
				//init color variable
				float4 col = 0;
			#if GAUSS
				float sum = 0;
			#else
				float sum = SAMPLES;
			#endif
				//iterate over blur samples
				for(float index = 0; index < SAMPLES; index++){
					//get the offset of the sample
					float offset = (index/(SAMPLES-1) - 0.5) * _BlurSize * invAspect;
					//get uv coordinate of sample
					float2 uv = i.uv + float2(offset, 0);
				#if !GAUSS
					//simply add the color if we don't have a gaussian blur (box)
					col += tex2D(_MainTex, uv);
				#else
					//calculate the result of the gaussian function
					float stDevSquared = _StandardDeviation*_StandardDeviation;
					float gauss = (1 / sqrt(2*PI*stDevSquared)) * pow(E, -((offset*offset)/(2*stDevSquared)));
					//add result to sum
					sum += gauss;
					//multiply color with influence from gaussian function and add it to sum color
					col += tex2D(_MainTex, uv) * gauss;
				#endif
				}
				//divide the sum of values by the amount of samples
				col = col / sum;
				return col;
			}

			ENDCG
		}*/
    }
}