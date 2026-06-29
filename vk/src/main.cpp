// MINECOASTER — Vulkan renderer (offscreen core).
//
// First increment of the raylib->Vulkan rewrite: a headless offscreen renderer
// that builds the game world (ported terrain/biome) as GPU meshes and renders one
// frame to a PPM. Cross-platform-ready (no surface deps yet); SDL2 windowing and
// the track/train/physics/path-tracer port land on top of this core.
//
// Build: see ../CMakeLists.txt. Headless test: lvp (lavapipe) + this exe.
#include <vulkan/vulkan.h>
#include "Math.h"
#include "Terrain.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include <stdexcept>

#define VK_CHECK(x) do { VkResult _r=(x); if(_r!=VK_SUCCESS){ \
    fprintf(stderr,"VK error %d at %s:%d\n",_r,__FILE__,__LINE__); exit(1);} } while(0)

struct PushConstants {
    Mat4 viewProj;
    float sunDir[4];
    float camPos[4];   // w = fog end
};

static std::vector<char> readFile(const std::string& p){
    FILE* f=fopen(p.c_str(),"rb"); if(!f){ fprintf(stderr,"cannot open %s\n",p.c_str()); exit(1);}
    fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET);
    std::vector<char> b(n); fread(b.data(),1,n,f); fclose(f); return b;
}

static uint32_t findMemType(VkPhysicalDevice pd, uint32_t bits, VkMemoryPropertyFlags want){
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd,&mp);
    for(uint32_t i=0;i<mp.memoryTypeCount;i++)
        if((bits&(1u<<i)) && (mp.memoryTypes[i].propertyFlags&want)==want) return i;
    fprintf(stderr,"no suitable memory type\n"); exit(1);
}

struct Buffer { VkBuffer buf=VK_NULL_HANDLE; VkDeviceMemory mem=VK_NULL_HANDLE; };

static Buffer makeBuffer(VkPhysicalDevice pd, VkDevice dev, VkDeviceSize size,
                         VkBufferUsageFlags usage, VkMemoryPropertyFlags props){
    Buffer b;
    VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bi.size=size; bi.usage=usage; bi.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    VK_CHECK(vkCreateBuffer(dev,&bi,nullptr,&b.buf));
    VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,b.buf,&mr);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=mr.size; ai.memoryTypeIndex=findMemType(pd,mr.memoryTypeBits,props);
    VK_CHECK(vkAllocateMemory(dev,&ai,nullptr,&b.mem));
    VK_CHECK(vkBindBufferMemory(dev,b.buf,b.mem,0));
    return b;
}

static VkShaderModule makeShader(VkDevice dev, const std::string& path){
    auto code=readFile(path);
    VkShaderModuleCreateInfo ci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    ci.codeSize=code.size(); ci.pCode=reinterpret_cast<const uint32_t*>(code.data());
    VkShaderModule m; VK_CHECK(vkCreateShaderModule(dev,&ci,nullptr,&m)); return m;
}

int main(int argc, char** argv){
    const uint32_t W = 1280, H = 720;
    std::string shaderDir = "shaders";
    std::string outPath = "minecoaster_vk.ppm";
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--shaders") && i+1<argc) shaderDir=argv[++i];
        else if(!strcmp(argv[i],"-o") && i+1<argc) outPath=argv[++i];
    }

    // ---- instance (offscreen: no surface/swapchain extensions) ----
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName="minecoaster_vk"; app.apiVersion=VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo=&app;
    VkInstance inst; VK_CHECK(vkCreateInstance(&ici,nullptr,&inst));

    // ---- physical + queue ----
    uint32_t npd=0; vkEnumeratePhysicalDevices(inst,&npd,nullptr);
    if(!npd){ fprintf(stderr,"no Vulkan devices\n"); return 1; }
    std::vector<VkPhysicalDevice> pds(npd); vkEnumeratePhysicalDevices(inst,&npd,pds.data());
    VkPhysicalDevice pd=pds[0];
    { VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd,&p);
      printf("[vk] device: %s\n", p.deviceName); }

    uint32_t nqf=0; vkGetPhysicalDeviceQueueFamilyProperties(pd,&nqf,nullptr);
    std::vector<VkQueueFamilyProperties> qfs(nqf);
    vkGetPhysicalDeviceQueueFamilyProperties(pd,&nqf,qfs.data());
    uint32_t gfx=UINT32_MAX;
    for(uint32_t i=0;i<nqf;i++) if(qfs[i].queueFlags&VK_QUEUE_GRAPHICS_BIT){ gfx=i; break; }
    if(gfx==UINT32_MAX){ fprintf(stderr,"no graphics queue\n"); return 1; }

    float prio=1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex=gfx; qci.queueCount=1; qci.pQueuePriorities=&prio;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount=1; dci.pQueueCreateInfos=&qci;
    VkDevice dev; VK_CHECK(vkCreateDevice(pd,&dci,nullptr,&dev));
    VkQueue queue; vkGetDeviceQueue(dev,gfx,0,&queue);

    // ---- offscreen color + depth images ----
    const VkFormat COLOR_FMT=VK_FORMAT_R8G8B8A8_UNORM, DEPTH_FMT=VK_FORMAT_D32_SFLOAT;
    auto makeImage=[&](VkFormat fmt, VkImageUsageFlags usage, VkImageAspectFlags aspect,
                       VkImage&img, VkDeviceMemory&mem, VkImageView&view){
        VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        ii.imageType=VK_IMAGE_TYPE_2D; ii.format=fmt; ii.extent={W,H,1};
        ii.mipLevels=1; ii.arrayLayers=1; ii.samples=VK_SAMPLE_COUNT_1_BIT;
        ii.tiling=VK_IMAGE_TILING_OPTIMAL; ii.usage=usage;
        ii.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED;
        VK_CHECK(vkCreateImage(dev,&ii,nullptr,&img));
        VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev,img,&mr);
        VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        ai.allocationSize=mr.size; ai.memoryTypeIndex=findMemType(pd,mr.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        VK_CHECK(vkAllocateMemory(dev,&ai,nullptr,&mem));
        VK_CHECK(vkBindImageMemory(dev,img,mem,0));
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vi.image=img; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=fmt;
        vi.subresourceRange={aspect,0,1,0,1};
        VK_CHECK(vkCreateImageView(dev,&vi,nullptr,&view));
    };
    VkImage colorImg,depthImg; VkDeviceMemory colorMem,depthMem; VkImageView colorView,depthView;
    makeImage(COLOR_FMT, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
              VK_IMAGE_ASPECT_COLOR_BIT, colorImg,colorMem,colorView);
    makeImage(DEPTH_FMT, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
              VK_IMAGE_ASPECT_DEPTH_BIT, depthImg,depthMem,depthView);

    // ---- render pass ----
    VkAttachmentDescription atts[2]{};
    atts[0].format=COLOR_FMT; atts[0].samples=VK_SAMPLE_COUNT_1_BIT;
    atts[0].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; atts[0].storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    atts[0].stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE; atts[0].stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[0].initialLayout=VK_IMAGE_LAYOUT_UNDEFINED; atts[0].finalLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    atts[1].format=DEPTH_FMT; atts[1].samples=VK_SAMPLE_COUNT_1_BIT;
    atts[1].loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; atts[1].storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[1].stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE; atts[1].stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    atts[1].initialLayout=VK_IMAGE_LAYOUT_UNDEFINED; atts[1].finalLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    VkAttachmentReference colorRef{0,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkAttachmentReference depthRef{1,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    VkSubpassDescription sub{}; sub.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount=1; sub.pColorAttachments=&colorRef; sub.pDepthStencilAttachment=&depthRef;
    VkSubpassDependency dep{}; dep.srcSubpass=VK_SUBPASS_EXTERNAL; dep.dstSubpass=0;
    dep.srcStageMask=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstStageMask=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo rpi{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    rpi.attachmentCount=2; rpi.pAttachments=atts; rpi.subpassCount=1; rpi.pSubpasses=&sub;
    rpi.dependencyCount=1; rpi.pDependencies=&dep;
    VkRenderPass rp; VK_CHECK(vkCreateRenderPass(dev,&rpi,nullptr,&rp));

    VkImageView fbViews[2]={colorView,depthView};
    VkFramebufferCreateInfo fbi{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
    fbi.renderPass=rp; fbi.attachmentCount=2; fbi.pAttachments=fbViews;
    fbi.width=W; fbi.height=H; fbi.layers=1;
    VkFramebuffer fb; VK_CHECK(vkCreateFramebuffer(dev,&fbi,nullptr,&fb));

    // ---- pipeline ----
    VkShaderModule vs=makeShader(dev,shaderDir+"/mesh.vert.spv");
    VkShaderModule fs=makeShader(dev,shaderDir+"/mesh.frag.spv");
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0]={VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    stages[0].stage=VK_SHADER_STAGE_VERTEX_BIT; stages[0].module=vs; stages[0].pName="main";
    stages[1]={VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    stages[1].stage=VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module=fs; stages[1].pName="main";

    VkVertexInputBindingDescription bind{0,sizeof(Vertex),VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attr[3]={
        {0,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,pos)},
        {1,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,nrm)},
        {2,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,col)} };
    VkPipelineVertexInputStateCreateInfo vin{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vin.vertexBindingDescriptionCount=1; vin.pVertexBindingDescriptions=&bind;
    vin.vertexAttributeDescriptionCount=3; vin.pVertexAttributeDescriptions=attr;

    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkViewport vp{0,0,(float)W,(float)H,0,1}; VkRect2D sc{{0,0},{W,H}};
    VkPipelineViewportStateCreateInfo vps{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vps.viewportCount=1; vps.pViewports=&vp; vps.scissorCount=1; vps.pScissors=&sc;

    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode=VK_POLYGON_MODE_FILL; rs.cullMode=VK_CULL_MODE_NONE;
    rs.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE; rs.lineWidth=1.0f;

    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT;

    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable=VK_TRUE; ds.depthWriteEnable=VK_TRUE; ds.depthCompareOp=VK_COMPARE_OP_LESS;

    VkPipelineColorBlendAttachmentState cba{}; cba.colorWriteMask=0xF;
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount=1; cb.pAttachments=&cba;

    VkPushConstantRange pcr{VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(PushConstants)};
    VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pli.pushConstantRangeCount=1; pli.pPushConstantRanges=&pcr;
    VkPipelineLayout layout; VK_CHECK(vkCreatePipelineLayout(dev,&pli,nullptr,&layout));

    VkGraphicsPipelineCreateInfo gpi{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    gpi.stageCount=2; gpi.pStages=stages; gpi.pVertexInputState=&vin; gpi.pInputAssemblyState=&ia;
    gpi.pViewportState=&vps; gpi.pRasterizationState=&rs; gpi.pMultisampleState=&ms;
    gpi.pDepthStencilState=&ds; gpi.pColorBlendState=&cb; gpi.layout=layout; gpi.renderPass=rp; gpi.subpass=0;
    VkPipeline pipe; VK_CHECK(vkCreateGraphicsPipelines(dev,VK_NULL_HANDLE,1,&gpi,nullptr,&pipe));

    // ---- world mesh ----
    const float CX=0, CZ=0, HALF=240.0f, STEP=1.5f;
    Mesh mesh; world::buildTerrain(CX,CZ,HALF,STEP,mesh); world::appendWater(CX,CZ,HALF,mesh);
    printf("[vk] world mesh: %zu verts, %zu indices (%zu tris)\n",
           mesh.verts.size(), mesh.idx.size(), mesh.idx.size()/3);

    VkDeviceSize vbSize=mesh.verts.size()*sizeof(Vertex), ibSize=mesh.idx.size()*sizeof(uint32_t);
    Buffer vb=makeBuffer(pd,dev,vbSize,VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    Buffer ib=makeBuffer(pd,dev,ibSize,VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    void* p;
    vkMapMemory(dev,vb.mem,0,vbSize,0,&p); memcpy(p,mesh.verts.data(),vbSize); vkUnmapMemory(dev,vb.mem);
    vkMapMemory(dev,ib.mem,0,ibSize,0,&p); memcpy(p,mesh.idx.data(),ibSize); vkUnmapMemory(dev,ib.mem);

    Buffer readback=makeBuffer(pd,dev,(VkDeviceSize)W*H*4,VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    // ---- camera + push constants ----
    Vec3 target{CX, (float)world::terrainH(CX,CZ)+10.0f, CZ};
    Vec3 eye = target + Vec3{170.0f, 160.0f, 170.0f};
    Mat4 view=lookAt(eye,target,Vec3{0,1,0});
    Mat4 proj=perspectiveVk(1.05f,(float)W/(float)H,0.5f,3000.0f);
    PushConstants pc{}; pc.viewProj=mul(proj,view);
    Vec3 sun=normalize(Vec3{-0.48f,0.60f,0.64f});
    pc.sunDir[0]=sun.x; pc.sunDir[1]=sun.y; pc.sunDir[2]=sun.z; pc.sunDir[3]=0;
    pc.camPos[0]=eye.x; pc.camPos[1]=eye.y; pc.camPos[2]=eye.z; pc.camPos[3]=HALF*3.6f;

    // ---- command buffer ----
    VkCommandPoolCreateInfo cpi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    cpi.queueFamilyIndex=gfx;
    VkCommandPool pool; VK_CHECK(vkCreateCommandPool(dev,&cpi,nullptr,&pool));
    VkCommandBufferAllocateInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cbi.commandPool=pool; cbi.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbi.commandBufferCount=1;
    VkCommandBuffer cmd; VK_CHECK(vkAllocateCommandBuffers(dev,&cbi,&cmd));

    VkCommandBufferBeginInfo bbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bbi.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkBeginCommandBuffer(cmd,&bbi));

    VkClearValue clears[2]; clears[0].color={{0.55f,0.70f,0.95f,1.0f}}; clears[1].depthStencil={1.0f,0};
    VkRenderPassBeginInfo rbi{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    rbi.renderPass=rp; rbi.framebuffer=fb; rbi.renderArea={{0,0},{W,H}};
    rbi.clearValueCount=2; rbi.pClearValues=clears;
    vkCmdBeginRenderPass(cmd,&rbi,VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(cmd,VK_PIPELINE_BIND_POINT_GRAPHICS,pipe);
    vkCmdPushConstants(cmd,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(pc),&pc);
    VkDeviceSize off=0;
    vkCmdBindVertexBuffers(cmd,0,1,&vb.buf,&off);
    vkCmdBindIndexBuffer(cmd,ib.buf,0,VK_INDEX_TYPE_UINT32);
    vkCmdDrawIndexed(cmd,(uint32_t)mesh.idx.size(),1,0,0,0);
    vkCmdEndRenderPass(cmd);

    // color image is now TRANSFER_SRC_OPTIMAL (render pass final layout) -> copy out
    VkBufferImageCopy region{}; region.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1};
    region.imageExtent={W,H,1};
    vkCmdCopyImageToBuffer(cmd,colorImg,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,readback.buf,1,&region);
    VK_CHECK(vkEndCommandBuffer(cmd));

    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence; VK_CHECK(vkCreateFence(dev,&fci,nullptr,&fence));
    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO}; si.commandBufferCount=1; si.pCommandBuffers=&cmd;
    VK_CHECK(vkQueueSubmit(queue,1,&si,fence));
    VK_CHECK(vkWaitForFences(dev,1,&fence,VK_TRUE,UINT64_MAX));

    // ---- write PPM (P6, RGB) ----
    void* mapped; vkMapMemory(dev,readback.mem,0,(VkDeviceSize)W*H*4,0,&mapped);
    const uint8_t* px=(const uint8_t*)mapped;
    FILE* of=fopen(outPath.c_str(),"wb");
    fprintf(of,"P6\n%u %u\n255\n",W,H);
    std::vector<uint8_t> row(W*3);
    for(uint32_t y=0;y<H;y++){ for(uint32_t x=0;x<W;x++){ const uint8_t* q=px+((size_t)y*W+x)*4;
        row[x*3+0]=q[0]; row[x*3+1]=q[1]; row[x*3+2]=q[2]; } fwrite(row.data(),1,row.size(),of); }
    fclose(of);
    vkUnmapMemory(dev,readback.mem);
    printf("[vk] wrote %s (%ux%u)\n", outPath.c_str(), W, H);

    // ---- teardown ----
    vkDestroyFence(dev,fence,nullptr);
    vkDestroyCommandPool(dev,pool,nullptr);
    vkDestroyPipeline(dev,pipe,nullptr); vkDestroyPipelineLayout(dev,layout,nullptr);
    vkDestroyShaderModule(dev,vs,nullptr); vkDestroyShaderModule(dev,fs,nullptr);
    vkDestroyFramebuffer(dev,fb,nullptr); vkDestroyRenderPass(dev,rp,nullptr);
    vkDestroyImageView(dev,colorView,nullptr); vkDestroyImageView(dev,depthView,nullptr);
    vkDestroyImage(dev,colorImg,nullptr); vkDestroyImage(dev,depthImg,nullptr);
    vkFreeMemory(dev,colorMem,nullptr); vkFreeMemory(dev,depthMem,nullptr);
    for(Buffer* b:{&vb,&ib,&readback}){ vkDestroyBuffer(dev,b->buf,nullptr); vkFreeMemory(dev,b->mem,nullptr); }
    vkDestroyDevice(dev,nullptr); vkDestroyInstance(inst,nullptr);
    return 0;
}
