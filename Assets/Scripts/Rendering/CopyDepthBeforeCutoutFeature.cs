using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;

public class CopyDepthBeforeCutoutFeature : ScriptableRendererFeature
{
    class CopyDepthPass : ScriptableRenderPass
    {
        private static readonly int _BehindDepthID = Shader.PropertyToID("_BehindAlphaTestDepthTexture");

        public CopyDepthPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            if (resourceData.isActiveTargetBackBuffer) return;

            TextureHandle activeDepth = resourceData.activeDepthTexture;
            if (!activeDepth.IsValid()) return;

            TextureDesc desc = renderGraph.GetTextureDesc(activeDepth);
            desc.name = "_BehindAlphaTestDepthTexture";
            desc.format = GraphicsFormat.R32_SFloat;
            desc.depthBufferBits = 0;
            desc.msaaSamples = MSAASamples.None;
            desc.clearBuffer = false;

            TextureHandle copiedDepth = renderGraph.CreateTexture(desc);

            // 1. Copy depth into our R32_SFloat texture
            renderGraph.AddBlitPass(activeDepth, copiedDepth, Vector2.one, Vector2.zero, passName: "Copy Depth Before AlphaTest");

            // 2. Bind globally for all subsequent passes (including Render Objects)
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Bind Behind Depth", out _))
            {
                builder.AllowPassCulling(false);
                builder.AllowGlobalStateModification(true); // <-- Fixes the InvalidOperationException
                builder.SetGlobalTextureAfterPass(copiedDepth, _BehindDepthID);
                builder.SetRenderFunc((PassData _, RasterGraphContext _) => { });
            }
        }

        private class PassData { }
    }

    private CopyDepthPass _pass;

    public override void Create()
    {
        _pass = new CopyDepthPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(_pass);
    }
}
