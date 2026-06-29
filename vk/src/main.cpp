// MINECOASTER — Vulkan renderer.
//
// Two modes:
//   (default)        interactive SDL2 window + swapchain + WASD/mouse fly camera
//   --shot -o f.ppm  render one frame offscreen to a PPM (headless, no surface)
//
// The raylib->Vulkan rewrite: terrain (voxel), the real coaster generator, and a
// PBR (Cook-Torrance) forward shader. Deferred/HDR + screen-space effects build on
// this. Cross-platform (Win/Linux native, macOS via MoltenVK).
#include <vulkan/vulkan.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_vulkan.h>

#include "Math.h"
#include "Terrain.h"
#include "Track.h"
#include "CoasterTrack.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

#define VK_CHECK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){ \
    fprintf(stderr,"VK error %d at %s:%d\n",_r,__FILE__,__LINE__); exit(1);} } while(0)

struct PushConstants { Mat4 viewProj; float sunDir[4]; float camPos[4]; };

static std::vector<char> readFile(const std::string& p){
    FILE* f=fopen(p.c_str(),"rb"); if(!f){ fprintf(stderr,"cannot open %s\n",p.c_str()); exit(1);}
    fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET);
    std::vector<char> b(n); size_t rd=fread(b.data(),1,n,f); (void)rd; fclose(f); return b;
}
static uint32_t findMemType(VkPhysicalDevice pd, uint32_t bits, VkMemoryPropertyFlags want){
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
    for(uint32_t i=0;i<mp.memoryTypeCount;i++)
        if((bits&(1u<<i)) && (mp.memoryTypes[i].propertyFlags&want)==want) return i;
    fprintf(stderr,"no memory type\n"); exit(1);
}
struct Buffer { VkBuffer buf=VK_NULL_HANDLE; VkDeviceMemory mem=VK_NULL_HANDLE; };
static Buffer makeBuffer(VkPhysicalDevice pd, VkDevice dev, VkDeviceSize size,
                         VkBufferUsageFlags usage, VkMemoryPropertyFlags props){
    Buffer b; VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bi.size=size; bi.usage=usage; bi.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    VK_CHECK(vkCreateBuffer(dev,&bi,nullptr,&b.buf));
    VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,b.buf,&mr);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=mr.size; ai.memoryTypeIndex=findMemType(pd,mr.memoryTypeBits,props);
    VK_CHECK(vkAllocateMemory(dev,&ai,nullptr,&b.mem));
    VK_CHECK(vkBindBufferMemory(dev,b.buf,b.mem,0)); return b;
}
static VkShaderModule makeShader(VkDevice dev, const std::string& path){
    auto code=readFile(path); VkShaderModuleCreateInfo ci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    ci.codeSize=code.size(); ci.pCode=reinterpret_cast<const uint32_t*>(code.data());
    VkShaderModule m; VK_CHECK(vkCreateShaderModule(dev,&ci,nullptr,&m)); return m;
}

static const VkFormat DEPTH_FMT = VK_FORMAT_D32_SFLOAT;

// depth image for a given extent
struct DepthRT { VkImage img; VkDeviceMemory mem; VkImageView view; };
static DepthRT makeDepth(VkPhysicalDevice pd, VkDevice dev, uint32_t W, uint32_t H){
    DepthRT d{};
    VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ii.imageType=VK_IMAGE_TYPE_2D; ii.format=DEPTH_FMT; ii.extent={W,H,1};
    ii.mipLevels=1; ii.arrayLayers=1; ii.samples=VK_SAMPLE_COUNT_1_BIT;
    ii.tiling=VK_IMAGE_TILING_OPTIMAL; ii.usage=VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    VK_CHECK(vkCreateImage(dev,&ii,nullptr,&d.img));
    VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,d.img,&mr);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=mr.size; ai.memoryTypeIndex=findMemType(pd,mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    VK_CHECK(vkAllocateMemory(dev,&ai,nullptr,&d.mem)); VK_CHECK(vkBindImageMemory(dev,d.img,d.mem,0));
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image=d.img; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=DEPTH_FMT;
    vi.subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1};
    VK_CHECK(vkCreateImageView(dev,&vi,nullptr,&d.view)); return d;
}

static VkRenderPass makeRenderPass(VkDevice dev, VkFormat color, VkImageLayout finalColor){
    VkAttachmentDescription a[2]{};
    a[0].format=color; a[0].samples=VK_SAMPLE_COUNT_1_BIT;
    a[0].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; a[0].storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    a[0].stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE; a[0].stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    a[0].initialLayout=VK_IMAGE_LAYOUT_UNDEFINED; a[0].finalLayout=finalColor;
    a[1].format=DEPTH_FMT; a[1].samples=VK_SAMPLE_COUNT_1_BIT;
    a[1].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; a[1].storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    a[1].stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE; a[1].stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    a[1].initialLayout=VK_IMAGE_LAYOUT_UNDEFINED; a[1].finalLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    VkAttachmentReference cr{0,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkAttachmentReference dr{1,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    VkSubpassDescription s{}; s.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS;
    s.colorAttachmentCount=1; s.pColorAttachments=&cr; s.pDepthStencilAttachment=&dr;
    VkSubpassDependency dep{}; dep.srcSubpass=VK_SUBPASS_EXTERNAL; dep.dstSubpass=0;
    dep.srcStageMask=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstStageMask=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT|VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo rp{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    rp.attachmentCount=2; rp.pAttachments=a; rp.subpassCount=1; rp.pSubpasses=&s;
    rp.dependencyCount=1; rp.pDependencies=&dep;
    VkRenderPass out; VK_CHECK(vkCreateRenderPass(dev,&rp,nullptr,&out)); return out;
}

// dynamic-viewport graphics pipeline shared by both modes
static VkPipeline makePipeline(VkDevice dev, VkRenderPass rp, VkPipelineLayout layout,
                               VkShaderModule vs, VkShaderModule fs){
    VkPipelineShaderStageCreateInfo st[2]{};
    st[0]={VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}; st[0].stage=VK_SHADER_STAGE_VERTEX_BIT; st[0].module=vs; st[0].pName="main";
    st[1]={VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}; st[1].stage=VK_SHADER_STAGE_FRAGMENT_BIT; st[1].module=fs; st[1].pName="main";
    VkVertexInputBindingDescription bind{0,sizeof(Vertex),VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription at[3]={
        {0,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,pos)},
        {1,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,nrm)},
        {2,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,col)} };
    VkPipelineVertexInputStateCreateInfo vin{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vin.vertexBindingDescriptionCount=1; vin.pVertexBindingDescriptions=&bind;
    vin.vertexAttributeDescriptionCount=3; vin.pVertexAttributeDescriptions=at;
    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount=1; vp.scissorCount=1;
    VkDynamicState dyn[2]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    ds.dynamicStateCount=2; ds.pDynamicStates=dyn;
    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode=VK_POLYGON_MODE_FILL; rs.cullMode=VK_CULL_MODE_NONE; rs.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE; rs.lineWidth=1.0f;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depth{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    depth.depthTestEnable=VK_TRUE; depth.depthWriteEnable=VK_TRUE; depth.depthCompareOp=VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState cba{}; cba.colorWriteMask=0xF;
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount=1; cb.pAttachments=&cba;
    VkGraphicsPipelineCreateInfo gp{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    gp.stageCount=2; gp.pStages=st; gp.pVertexInputState=&vin; gp.pInputAssemblyState=&ia;
    gp.pViewportState=&vp; gp.pRasterizationState=&rs; gp.pMultisampleState=&ms;
    gp.pDepthStencilState=&depth; gp.pColorBlendState=&cb; gp.pDynamicState=&ds;
    gp.layout=layout; gp.renderPass=rp; gp.subpass=0;
    VkPipeline pipe; VK_CHECK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gp,nullptr,&pipe)); return pipe;
}

// ---- world ----
struct World { Mesh mesh; Vec3 focus; };
static World buildWorld(){
    World w; ::Track trk; world::genLongTrack(trk,2200);
    w.focus=world::trackFocus(trk,260); float half=170.0f;
    world::buildTerrain(w.focus.x,w.focus.z,half,1.0f,w.mesh);
    world::appendWater(w.focus.x,w.focus.z,half,w.mesh);
    world::buildTrackMesh(trk,w.mesh,w.focus.x,w.focus.z,half);
    printf("[vk] world mesh: %zu verts, %zu tris\n", w.mesh.verts.size(), w.mesh.idx.size()/3);
    return w;
}

struct FlyCam {
    Vec3 pos; float yaw=-2.2f, pitch=-0.32f;
    Vec3 fwd() const { float cp=cosf(pitch),sp=sinf(pitch),cy=cosf(yaw),sy=sinf(yaw);
                       return normalize(Vec3{cp*sy, sp, cp*cy}); }
    Mat4 viewProj(float aspect) const {
        Vec3 f=fwd(); return mul(perspectiveVk(1.05f,aspect,0.4f,4000.0f), lookAt(pos,pos+f,Vec3{0,1,0}));
    }
};
static void fillPC(PushConstants& pc, const FlyCam& cam, float aspect){
    pc.viewProj=cam.viewProj(aspect);
    Vec3 sun=normalize(Vec3{-0.48f,0.60f,0.64f});
    pc.sunDir[0]=sun.x; pc.sunDir[1]=sun.y; pc.sunDir[2]=sun.z; pc.sunDir[3]=0;
    pc.camPos[0]=cam.pos.x; pc.camPos[1]=cam.pos.y; pc.camPos[2]=cam.pos.z; pc.camPos[3]=620.0f;
}

// =====================================================================
// Offscreen (headless) — render one frame to a PPM
// =====================================================================
static int runOffscreen(const World& world, const std::string& shaderDir, const std::string& outPath){
    const uint32_t W=1280,H=720; const VkFormat COLOR=VK_FORMAT_R8G8B8A8_UNORM;
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO}; app.apiVersion=VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO}; ici.pApplicationInfo=&app;
    VkInstance inst; VK_CHECK(vkCreateInstance(&ici,nullptr,&inst));
    uint32_t n=0; vkEnumeratePhysicalDevices(inst,&n,nullptr); std::vector<VkPhysicalDevice> pds(n);
    vkEnumeratePhysicalDevices(inst,&n,pds.data()); VkPhysicalDevice pd=pds[0];
    uint32_t nq=0; vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,nullptr); std::vector<VkQueueFamilyProperties> qf(nq);
    vkGetPhysicalDeviceQueueFamilyProperties(pd,&nq,qf.data()); uint32_t gfx=0;
    for(uint32_t i=0;i<nq;i++) if(qf[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){gfx=i;break;}
    float pr=1; VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO}; qci.queueFamilyIndex=gfx; qci.queueCount=1; qci.pQueuePriorities=&pr;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO}; dci.queueCreateInfoCount=1; dci.pQueueCreateInfos=&qci;
    VkDevice dev; VK_CHECK(vkCreateDevice(pd,&dci,nullptr,&dev)); VkQueue queue; vkGetDeviceQueue(dev,gfx,0,&queue);

    // color image (TRANSFER_SRC for readback)
    VkImage cimg; VkDeviceMemory cmem; VkImageView cview;
    { VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO}; ii.imageType=VK_IMAGE_TYPE_2D; ii.format=COLOR;
      ii.extent={W,H,1}; ii.mipLevels=1; ii.arrayLayers=1; ii.samples=VK_SAMPLE_COUNT_1_BIT; ii.tiling=VK_IMAGE_TILING_OPTIMAL;
      ii.usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
      VK_CHECK(vkCreateImage(dev,&ii,nullptr,&cimg)); VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,cimg,&mr);
      VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; ai.allocationSize=mr.size; ai.memoryTypeIndex=findMemType(pd,mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
      VK_CHECK(vkAllocateMemory(dev,&ai,nullptr,&cmem)); VK_CHECK(vkBindImageMemory(dev,cimg,cmem,0));
      VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO}; vi.image=cimg; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=COLOR;
      vi.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}; VK_CHECK(vkCreateImageView(dev,&vi,nullptr,&cview)); }
    DepthRT depth=makeDepth(pd,dev,W,H);
    VkRenderPass rp=makeRenderPass(dev,COLOR,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    VkImageView fbv[2]={cview,depth.view};
    VkFramebufferCreateInfo fbi{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO}; fbi.renderPass=rp; fbi.attachmentCount=2; fbi.pAttachments=fbv; fbi.width=W; fbi.height=H; fbi.layers=1;
    VkFramebuffer fb; VK_CHECK(vkCreateFramebuffer(dev,&fbi,nullptr,&fb));
    VkShaderModule vs=makeShader(dev,shaderDir+"/mesh.vert.spv"), fs=makeShader(dev,shaderDir+"/mesh.frag.spv");
    VkPushConstantRange pcr{VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(PushConstants)};
    VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO}; pli.pushConstantRangeCount=1; pli.pPushConstantRanges=&pcr;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(dev,&pli,nullptr,&layout));
    VkPipeline pipe=makePipeline(dev,rp,layout,vs,fs);

    VkDeviceSize vbS=world.mesh.verts.size()*sizeof(Vertex), ibS=world.mesh.idx.size()*sizeof(uint32_t);
    Buffer vb=makeBuffer(pd,dev,vbS,VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    Buffer ib=makeBuffer(pd,dev,ibS,VK_BUFFER_USAGE_INDEX_BUFFER_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    void* p; vkMapMemory(dev,vb.mem,0,vbS,0,&p); memcpy(p,world.mesh.verts.data(),vbS); vkUnmapMemory(dev,vb.mem);
    vkMapMemory(dev,ib.mem,0,ibS,0,&p); memcpy(p,world.mesh.idx.data(),ibS); vkUnmapMemory(dev,ib.mem);
    Buffer rb=makeBuffer(pd,dev,(VkDeviceSize)W*H*4,VK_BUFFER_USAGE_TRANSFER_DST_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    FlyCam cam; cam.pos = world.focus + Vec3{135,98,165};
    PushConstants pc; fillPC(pc,cam,(float)W/H);

    VkCommandPoolCreateInfo cpi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO}; cpi.queueFamilyIndex=gfx;
    VkCommandPool pool; VK_CHECK(vkCreateCommandPool(dev,&cpi,nullptr,&pool));
    VkCommandBufferAllocateInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO}; cbi.commandPool=pool; cbi.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbi.commandBufferCount=1;
    VkCommandBuffer cmd; VK_CHECK(vkAllocateCommandBuffers(dev,&cbi,&cmd));
    VkCommandBufferBeginInfo bbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; bbi.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkBeginCommandBuffer(cmd,&bbi));
    VkClearValue cl[2]; cl[0].color={{0.45f,0.62f,0.92f,1}}; cl[1].depthStencil={1,0};
    VkRenderPassBeginInfo rbi{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO}; rbi.renderPass=rp; rbi.framebuffer=fb; rbi.renderArea={{0,0},{W,H}}; rbi.clearValueCount=2; rbi.pClearValues=cl;
    vkCmdBeginRenderPass(cmd,&rbi,VK_SUBPASS_CONTENTS_INLINE);
    VkViewport vpt{0,0,(float)W,(float)H,0,1}; VkRect2D sc{{0,0},{W,H}};
    vkCmdSetViewport(cmd,0,1,&vpt); vkCmdSetScissor(cmd,0,1,&sc);
    vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
    vkCmdPushConstants(cmd,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(pc),&pc);
    VkDeviceSize off=0; vkCmdBindVertexBuffers(cmd,0,1,&vb.buf,&off); vkCmdBindIndexBuffer(cmd,ib.buf,0,VK_INDEX_TYPE_UINT32);
    vkCmdDrawIndexed(cmd,(uint32_t)world.mesh.idx.size(),1,0,0,0);
    vkCmdEndRenderPass(cmd);
    VkBufferImageCopy reg{}; reg.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1}; reg.imageExtent={W,H,1};
    vkCmdCopyImageToBuffer(cmd,cimg,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,rb.buf,1,&reg);
    VK_CHECK(vkEndCommandBuffer(cmd));
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; VkFence fence; VK_CHECK(vkCreateFence(dev,&fci,nullptr,&fence));
    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO}; si.commandBufferCount=1; si.pCommandBuffers=&cmd;
    VK_CHECK(vkQueueSubmit(queue,1,&si,fence)); VK_CHECK(vkWaitForFences(dev,1,&fence,VK_TRUE,UINT64_MAX));
    void* mp; vkMapMemory(dev,rb.mem,0,(VkDeviceSize)W*H*4,0,&mp); const uint8_t* px=(const uint8_t*)mp;
    FILE* of=fopen(outPath.c_str(),"wb"); fprintf(of,"P6\n%u %u\n255\n",W,H); std::vector<uint8_t> row(W*3);
    for(uint32_t y=0;y<H;y++){ for(uint32_t x=0;x<W;x++){ const uint8_t* q=px+((size_t)y*W+x)*4; row[x*3]=q[0]; row[x*3+1]=q[1]; row[x*3+2]=q[2]; } fwrite(row.data(),1,row.size(),of); }
    fclose(of); vkUnmapMemory(dev,rb.mem); printf("[vk] wrote %s\n",outPath.c_str());
    vkDeviceWaitIdle(dev); return 0;
}

// =====================================================================
// Windowed (interactive) — SDL2 + swapchain + fly camera
// =====================================================================
struct Swap {
    VkSwapchainKHR chain=VK_NULL_HANDLE; VkFormat fmt; VkExtent2D ext;
    std::vector<VkImage> images; std::vector<VkImageView> views; std::vector<VkFramebuffer> fbs;
    DepthRT depth{};
};
static void destroySwap(VkDevice dev, Swap& s){
    for(auto fb:s.fbs) vkDestroyFramebuffer(dev,fb,nullptr);
    for(auto v:s.views) vkDestroyImageView(dev,v,nullptr);
    if(s.depth.view){ vkDestroyImageView(dev,s.depth.view,nullptr); vkDestroyImage(dev,s.depth.img,nullptr); vkFreeMemory(dev,s.depth.mem,nullptr); }
    if(s.chain) vkDestroySwapchainKHR(dev,s.chain,nullptr);
    s.fbs.clear(); s.views.clear(); s.images.clear(); s.chain=VK_NULL_HANDLE; s.depth={};
}
static void createSwap(VkPhysicalDevice pd, VkDevice dev, VkSurfaceKHR surf, VkRenderPass& rp,
                       VkFormat& chosenFmt, Swap& s, uint32_t wantW, uint32_t wantH, bool haveRp){
    VkSurfaceCapabilitiesKHR caps; vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd,surf,&caps);
    uint32_t nf=0; vkGetPhysicalDeviceSurfaceFormatsKHR(pd,surf,&nf,nullptr); std::vector<VkSurfaceFormatKHR> fmts(nf);
    vkGetPhysicalDeviceSurfaceFormatsKHR(pd,surf,&nf,fmts.data());
    VkSurfaceFormatKHR sf=fmts[0];
    for(auto&f:fmts) if(f.format==VK_FORMAT_B8G8R8A8_UNORM){ sf=f; break; }
    s.fmt=sf.format; chosenFmt=sf.format;
    VkExtent2D ext=caps.currentExtent;
    if(ext.width==0xFFFFFFFF){ ext.width=wantW; ext.height=wantH; }
    s.ext=ext;
    uint32_t imgCount=caps.minImageCount+1; if(caps.maxImageCount && imgCount>caps.maxImageCount) imgCount=caps.maxImageCount;
    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface=surf; ci.minImageCount=imgCount; ci.imageFormat=sf.format; ci.imageColorSpace=sf.colorSpace;
    ci.imageExtent=ext; ci.imageArrayLayers=1; ci.imageUsage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.imageSharingMode=VK_SHARING_MODE_EXCLUSIVE; ci.preTransform=caps.currentTransform;
    ci.compositeAlpha=VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR; ci.presentMode=VK_PRESENT_MODE_FIFO_KHR; ci.clipped=VK_TRUE;
    VK_CHECK(vkCreateSwapchainKHR(dev,&ci,nullptr,&s.chain));
    uint32_t ni=0; vkGetSwapchainImagesKHR(dev,s.chain,&ni,nullptr); s.images.resize(ni);
    vkGetSwapchainImagesKHR(dev,s.chain,&ni,s.images.data());
    if(!haveRp) rp=makeRenderPass(dev,sf.format,VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    s.depth=makeDepth(pd,dev,ext.width,ext.height);
    s.views.resize(ni); s.fbs.resize(ni);
    for(uint32_t i=0;i<ni;i++){
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO}; vi.image=s.images[i]; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=sf.format;
        vi.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1}; VK_CHECK(vkCreateImageView(dev,&vi,nullptr,&s.views[i]));
        VkImageView av[2]={s.views[i],s.depth.view};
        VkFramebufferCreateInfo fbi{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO}; fbi.renderPass=rp; fbi.attachmentCount=2; fbi.pAttachments=av; fbi.width=ext.width; fbi.height=ext.height; fbi.layers=1;
        VK_CHECK(vkCreateFramebuffer(dev,&fbi,nullptr,&s.fbs[i]));
    }
}

static int runWindowed(const World& world, const std::string& shaderDir, int maxFrames){
    if(SDL_Init(SDL_INIT_VIDEO)!=0){ fprintf(stderr,"SDL_Init: %s\n",SDL_GetError()); return 1; }
    uint32_t W=1280,H=720;
    SDL_Window* win=SDL_CreateWindow("MINECOASTER (Vulkan)",SDL_WINDOWPOS_CENTERED,SDL_WINDOWPOS_CENTERED,W,H,
        SDL_WINDOW_VULKAN|SDL_WINDOW_RESIZABLE);
    if(!win){ fprintf(stderr,"SDL_CreateWindow: %s\n",SDL_GetError()); return 1; }

    uint32_t nExt=0; SDL_Vulkan_GetInstanceExtensions(win,&nExt,nullptr); std::vector<const char*> exts(nExt);
    SDL_Vulkan_GetInstanceExtensions(win,&nExt,exts.data());
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO}; app.apiVersion=VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO}; ici.pApplicationInfo=&app;
    ici.enabledExtensionCount=nExt; ici.ppEnabledExtensionNames=exts.data();
    VkInstance inst; VK_CHECK(vkCreateInstance(&ici,nullptr,&inst));
    VkSurfaceKHR surf; if(!SDL_Vulkan_CreateSurface(win,inst,&surf)){ fprintf(stderr,"CreateSurface: %s\n",SDL_GetError()); return 1; }

    uint32_t n=0; vkEnumeratePhysicalDevices(inst,&n,nullptr); std::vector<VkPhysicalDevice> pds(n);
    vkEnumeratePhysicalDevices(inst,&n,pds.data());
    VkPhysicalDevice pd=VK_NULL_HANDLE; uint32_t gfx=0;
    for(auto cand:pds){ uint32_t nq=0; vkGetPhysicalDeviceQueueFamilyProperties(cand,&nq,nullptr); std::vector<VkQueueFamilyProperties> qf(nq);
        vkGetPhysicalDeviceQueueFamilyProperties(cand,&nq,qf.data());
        for(uint32_t i=0;i<nq;i++){ VkBool32 present=VK_FALSE; vkGetPhysicalDeviceSurfaceSupportKHR(cand,i,surf,&present);
            if((qf[i].queueFlags&VK_QUEUE_GRAPHICS_BIT)&&present){ pd=cand; gfx=i; break; } }
        if(pd) break; }
    if(!pd){ fprintf(stderr,"no graphics+present device\n"); return 1; }
    { VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd,&p); printf("[vk] device: %s\n",p.deviceName); }

    const char* devExt[]={VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    float pr=1; VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO}; qci.queueFamilyIndex=gfx; qci.queueCount=1; qci.pQueuePriorities=&pr;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO}; dci.queueCreateInfoCount=1; dci.pQueueCreateInfos=&qci;
    dci.enabledExtensionCount=1; dci.ppEnabledExtensionNames=devExt;
    VkDevice dev; VK_CHECK(vkCreateDevice(pd,&dci,nullptr,&dev)); VkQueue queue; vkGetDeviceQueue(dev,gfx,0,&queue);

    VkRenderPass rp=VK_NULL_HANDLE; VkFormat fmt; Swap swap{};
    createSwap(pd,dev,surf,rp,fmt,swap,W,H,false);

    VkShaderModule vs=makeShader(dev,shaderDir+"/mesh.vert.spv"), fs=makeShader(dev,shaderDir+"/mesh.frag.spv");
    VkPushConstantRange pcr{VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(PushConstants)};
    VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO}; pli.pushConstantRangeCount=1; pli.pPushConstantRanges=&pcr;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(dev,&pli,nullptr,&layout));
    VkPipeline pipe=makePipeline(dev,rp,layout,vs,fs);

    VkDeviceSize vbS=world.mesh.verts.size()*sizeof(Vertex), ibS=world.mesh.idx.size()*sizeof(uint32_t);
    Buffer vb=makeBuffer(pd,dev,vbS,VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    Buffer ib=makeBuffer(pd,dev,ibS,VK_BUFFER_USAGE_INDEX_BUFFER_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    void* mp; vkMapMemory(dev,vb.mem,0,vbS,0,&mp); memcpy(mp,world.mesh.verts.data(),vbS); vkUnmapMemory(dev,vb.mem);
    vkMapMemory(dev,ib.mem,0,ibS,0,&mp); memcpy(mp,world.mesh.idx.data(),ibS); vkUnmapMemory(dev,ib.mem);

    VkCommandPoolCreateInfo cpi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO}; cpi.queueFamilyIndex=gfx; cpi.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    VkCommandPool pool; VK_CHECK(vkCreateCommandPool(dev,&cpi,nullptr,&pool));
    VkCommandBufferAllocateInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO}; cbi.commandPool=pool; cbi.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbi.commandBufferCount=1;
    VkCommandBuffer cmd; VK_CHECK(vkAllocateCommandBuffers(dev,&cbi,&cmd));
    VkSemaphoreCreateInfo sci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}; VkSemaphore semAcq,semDone;
    VK_CHECK(vkCreateSemaphore(dev,&sci,nullptr,&semAcq)); VK_CHECK(vkCreateSemaphore(dev,&sci,nullptr,&semDone));
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; fci.flags=VK_FENCE_CREATE_SIGNALED_BIT; VkFence fence; VK_CHECK(vkCreateFence(dev,&fci,nullptr,&fence));

    FlyCam cam; cam.pos = world.focus + Vec3{120,86,150};
    SDL_SetRelativeMouseMode(SDL_TRUE);
    printf("[vk] controls: WASD move, Q/E down/up, mouse look, Shift fast, Esc quit\n");

    bool run=true; uint32_t lastTicks=SDL_GetTicks(); int frame=0;
    while(run){
        uint32_t now=SDL_GetTicks(); float dt=(now-lastTicks)/1000.0f; lastTicks=now; if(dt>0.1f) dt=0.1f;
        SDL_Event e;
        while(SDL_PollEvent(&e)){
            if(e.type==SDL_QUIT) run=false;
            else if(e.type==SDL_KEYDOWN && e.key.keysym.sym==SDLK_ESCAPE) run=false;
            else if(e.type==SDL_MOUSEMOTION){ cam.yaw -= e.motion.xrel*0.0025f; cam.pitch -= e.motion.yrel*0.0025f;
                if(cam.pitch> 1.5f)cam.pitch=1.5f; if(cam.pitch<-1.5f)cam.pitch=-1.5f; }
            else if(e.type==SDL_WINDOWEVENT && e.window.event==SDL_WINDOWEVENT_SIZE_CHANGED){
                vkDeviceWaitIdle(dev); destroySwap(dev,swap); createSwap(pd,dev,surf,rp,fmt,swap,W,H,true); }
        }
        const Uint8* ks=SDL_GetKeyboardState(nullptr);
        Vec3 f=cam.fwd(), r=normalize(cross(f,Vec3{0,1,0}));
        float spd=(ks[SDL_SCANCODE_LSHIFT]?120.0f:38.0f)*dt;
        if(ks[SDL_SCANCODE_W]) cam.pos=cam.pos+f*spd;
        if(ks[SDL_SCANCODE_S]) cam.pos=cam.pos-f*spd;
        if(ks[SDL_SCANCODE_D]) cam.pos=cam.pos+r*spd;
        if(ks[SDL_SCANCODE_A]) cam.pos=cam.pos-r*spd;
        if(ks[SDL_SCANCODE_E]) cam.pos.y+=spd;
        if(ks[SDL_SCANCODE_Q]) cam.pos.y-=spd;

        VK_CHECK(vkWaitForFences(dev,1,&fence,VK_TRUE,UINT64_MAX));
        uint32_t idx; VkResult acq=vkAcquireNextImageKHR(dev,swap.chain,UINT64_MAX,semAcq,VK_NULL_HANDLE,&idx);
        if(acq==VK_ERROR_OUT_OF_DATE_KHR){ vkDeviceWaitIdle(dev); destroySwap(dev,swap); createSwap(pd,dev,surf,rp,fmt,swap,W,H,true); continue; }
        VK_CHECK(vkResetFences(dev,1,&fence));
        vkResetCommandBuffer(cmd,0);
        VkCommandBufferBeginInfo bbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        VK_CHECK(vkBeginCommandBuffer(cmd,&bbi));
        VkClearValue cl[2]; cl[0].color={{0.45f,0.62f,0.92f,1}}; cl[1].depthStencil={1,0};
        VkRenderPassBeginInfo rbi{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO}; rbi.renderPass=rp; rbi.framebuffer=swap.fbs[idx];
        rbi.renderArea={{0,0},swap.ext}; rbi.clearValueCount=2; rbi.pClearValues=cl;
        vkCmdBeginRenderPass(cmd,&rbi,VK_SUBPASS_CONTENTS_INLINE);
        VkViewport vpt{0,0,(float)swap.ext.width,(float)swap.ext.height,0,1}; VkRect2D scs{{0,0},swap.ext};
        vkCmdSetViewport(cmd,0,1,&vpt); vkCmdSetScissor(cmd,0,1,&scs);
        vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
        PushConstants pc; fillPC(pc,cam,(float)swap.ext.width/swap.ext.height);
        vkCmdPushConstants(cmd,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(pc),&pc);
        VkDeviceSize off=0; vkCmdBindVertexBuffers(cmd,0,1,&vb.buf,&off); vkCmdBindIndexBuffer(cmd,ib.buf,0,VK_INDEX_TYPE_UINT32);
        vkCmdDrawIndexed(cmd,(uint32_t)world.mesh.idx.size(),1,0,0,0);
        vkCmdEndRenderPass(cmd); VK_CHECK(vkEndCommandBuffer(cmd));
        VkPipelineStageFlags wait=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO}; si.waitSemaphoreCount=1; si.pWaitSemaphores=&semAcq; si.pWaitDstStageMask=&wait;
        si.commandBufferCount=1; si.pCommandBuffers=&cmd; si.signalSemaphoreCount=1; si.pSignalSemaphores=&semDone;
        VK_CHECK(vkQueueSubmit(queue,1,&si,fence));
        VkPresentInfoKHR ppi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR}; ppi.waitSemaphoreCount=1; ppi.pWaitSemaphores=&semDone; ppi.swapchainCount=1; ppi.pSwapchains=&swap.chain; ppi.pImageIndices=&idx;
        VkResult pres=vkQueuePresentKHR(queue,&ppi);
        if(pres==VK_ERROR_OUT_OF_DATE_KHR||pres==VK_SUBOPTIMAL_KHR){ vkDeviceWaitIdle(dev); destroySwap(dev,swap); createSwap(pd,dev,surf,rp,fmt,swap,W,H,true); }
        if(maxFrames>0 && ++frame>=maxFrames) run=false;
    }
    vkDeviceWaitIdle(dev);
    SDL_DestroyWindow(win); SDL_Quit();
    printf("[vk] windowed session ended\n");
    return 0;
}

int main(int argc, char** argv){
    std::string shaderDir="shaders", outPath="minecoaster_vk.ppm";
    bool shot=false; int maxFrames=0;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--shaders")&&i+1<argc) shaderDir=argv[++i];
        else if(!strcmp(argv[i],"-o")&&i+1<argc){ outPath=argv[++i]; shot=true; }
        else if(!strcmp(argv[i],"--shot")) shot=true;
        else if(!strcmp(argv[i],"--frames")&&i+1<argc) maxFrames=atoi(argv[++i]);
    }
    World world=buildWorld();
    return shot ? runOffscreen(world,shaderDir,outPath) : runWindowed(world,shaderDir,maxFrames);
}
