Shader "Custom/StylizedWater_SSRBackup"
{
    Properties
    {
        _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Float) = 1.0

        _ScrollSpeed("Scroll Speed", Vector, 2) = (0.1, 0.1, 0, 0)

        _Smoothness("Smoothness", Float) = 0.5
        _Occlusion("Occlusion", Float) = 1.0
        
        [HDR] _SpecColor("Specular Color", Color) = (1, 1, 1, 1)
        _SpecShininess("Specular Shininess", Float) = 32.0

        [Space(5.0)]
        _NearDepthColor("Near Depth Color", Color) = (1, 1, 1, 1)
        _FullDepthColor("Far Depth Color", Color) = (0.5, 0.5, 0.5, 1)
        _NearDepth("Near Depth", Float) = 5
        _FarDepth("Far Depth", Float) = 5
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" }

        // Required for screen space effects (afaik)
        UsePass "Universal Render Pipeline/Lit/DepthNormals"

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha

            // Useful for transparency and reflections
            // Also ensures we don't accidentally sample the current fragment in the depth buffer
            // ^ it always gets the depth of the fragment behind it
            ZWrite Off

            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            // Got from Unity Forums (Reflection Probes):
            // https://discussions.unity.com/t/how-to-sample-reflection-in-urp-shader-not-graph/1675584
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF		
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #if (UNITY_VERSION >= 60010000)
                #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
                #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #endif

            // Required for SSR
            #pragma multi_compile_fragment _ _SCREEN_SPACE_REFLECTION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" // For specular
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl" // Dependancy of GlobalIllumination.hlsl, literally won't compile without it
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl" // not sure if this is needed

            struct Attributes
            {
                float2 uv : TEXCOORD0;

                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;

                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
            };

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _NormalMap_ST;
                float _NormalStrength;

                float2 _ScrollSpeed;

                float _Smoothness;
                float _Occlusion;

                half4 _SpecColor;
                float _SpecShininess;

                half4 _NearDepthColor;
                half4 _FullDepthColor;
                float _NearDepth;
                float _FarDepth;

            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                float2 uv = IN.uv;
                uv += _ScrollSpeed * _Time.y;
                OUT.uv = TRANSFORM_TEX(uv, _NormalMap);

                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS = normalize(TransformObjectToWorldNormal(IN.tangentOS.xyz));
				OUT.bitangentWS = cross(OUT.normalWS, OUT.tangentWS) * IN.tangentOS.w;

                return OUT;
            }

            // Helper function for depth calculations
            // Used one of numerous functions given on forums, and converted it to HLSL
            float InverseLerp(float a, float b, float value)
            {
                return saturate((value - a) / (b - a));
            }

            half3 GetReflectionColor(float3 positionWS, float3 normalWS, float2 ssUV)
            {
                float3 N = SafeNormalize(normalWS);
                float3 V = SafeNormalize(GetWorldSpaceViewDir(positionWS));
                float3 R = reflect(-V, N);

                // Reflection Probes
                float3 probes = GlossyEnvironmentReflection(R, positionWS.xyz, PerceptualSmoothnessToPerceptualRoughness(_Smoothness), _Occlusion, ssUV);

                // Found via Google AI Overview and reading into its sources (like the following):
                // https://discussions.unity.com/t/preview-of-screen-space-reflections-for-urp/1721494/20
                float4 ssr = SampleScreenSpaceReflection(ssUV, positionWS, PerceptualSmoothnessToPerceptualRoughness(_Smoothness));
                
                // Lerp between reflection probes and SSR based on its fade weight (i.e. if object in reflection is out of view?)
                half3 color = lerp(probes, ssr.rgb, ssr.a);
                
                return color;
            }

            half4 ApplyDepthColor(half4 finalColor, float4 positionHCS)
            {
                // Most of the functions and definitions was found with Google AI Overview and its sources,
                // though I wrote the code myself and heavily modified that which was generated to suit my specific needs.
                // e.g. I only know the LinearEyeDepth functions from AI queries, but I use my own knowledge to decide what to do with the results
                // (calculate effective depth, inverse lerp, apply to fragment color)

                // Sample depth buffer
                // Tons of variations to do this, but this one seemed most likely to work with Transparent render queue (which it didn't)
                float2 screenUV = positionHCS.xy / _ScaledScreenParams.xy;
                float rawSceneDepth = SampleSceneDepth(screenUV);

                // Convert to linear depth value
                float belowObjDepthWS = LinearEyeDepth(rawSceneDepth, _ZBufferParams); // World space depth
                
                // Normalized based on camera near and far plane (hence the 01).
                // We don't need it here, but keeping it for future reference.
                //float 01Depth = Linear01Depth(rawDepth, _ZBufferParams);

                // Get depth of the current fragment (water surface)
                float waterDepthWS = LinearEyeDepth(positionHCS.z, _ZBufferParams);

                float t = InverseLerp(max(_NearDepth, 0), max(_FarDepth, _NearDepth), belowObjDepthWS - waterDepthWS);

                finalColor *= lerp(_NearDepthColor, _FullDepthColor, t);

                return finalColor;
            }

            half3 GetSpecular(half3 normalWS, half3 viewDirWS)
            {
                Light mainLight = GetMainLight();
				half3 lightDir = normalize(mainLight.direction);

				half3 reflectDir = reflect(-lightDir, normalWS);

				half3 viewDir = normalize(viewDirWS);
				half specFactor = pow(saturate(dot(reflectDir, viewDir)), max(_SpecShininess, 1));
				half3 specular = _SpecColor.rgb * specFactor;
                
				float nDotL = saturate(dot(normalWS, lightDir));
				return specular * nDotL;
            }

            half3 GetNormal(float2 uv, float3 normalWS, float3 tangentWS, float3 bitangentWS)
            {
                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv));

				normalTS.xy *= _NormalStrength;

				half3x3 TBN = half3x3(tangentWS, bitangentWS, normalWS);
				return normalize(mul(normalTS, TBN));
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 finalColor = half4(1, 1, 1, 1);

                half3 normalWS = GetNormal(IN.uv, IN.normalWS, IN.tangentWS, IN.bitangentWS);

                float2 ssUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
                
                // Reflections
                finalColor.rgb *= GetReflectionColor(IN.positionWS, normalWS, ssUV);

                // Depth coloring
                finalColor = ApplyDepthColor(finalColor, IN.positionHCS);

                // Specular
                finalColor.rgb += GetSpecular(normalWS, GetWorldSpaceViewDir(IN.positionWS));

                return finalColor;
            }

            ENDHLSL
        }
    }
}
