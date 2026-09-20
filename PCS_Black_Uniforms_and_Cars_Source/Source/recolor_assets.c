/* Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef struct { float x0, y0, x1, y1; } Rect;
typedef struct { uint32_t x, y; uint64_t offset; } Tile;
typedef struct { uint32_t w, h, count; Tile *tiles; } Mip;

static void fail(const char *s) { fprintf(stderr, "%s\n", s); exit(1); }
static void rd(FILE *f, void *p, size_t n) { if (fread(p, 1, n, f) != n) fail("Truncated job"); }
static uint32_t r32(FILE *f) { uint32_t v; rd(f, &v, 4); return v; }
static uint64_t r64(FILE *f) { uint64_t v; rd(f, &v, 8); return v; }
static unsigned short u16(const unsigned char *p) { return p[0] | (p[1] << 8); }
static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
static int wrap(int v, int n) { return (v % n + n) % n; }

static void rgb565(uint16_t v, unsigned char *c) {
    unsigned r = v >> 11, g = (v >> 5) & 63, b = v & 31;
    c[0] = (r << 3) | (r >> 2);
    c[1] = (g << 2) | (g >> 4);
    c[2] = (b << 3) | (b >> 2);
}

static uint16_t to565(const unsigned char *c) {
    return ((c[0] * 31 + 127) / 255 << 11) | ((c[1] * 63 + 127) / 255 << 5) | ((c[2] * 31 + 127) / 255);
}

static void palette(uint16_t a, uint16_t b, unsigned char p[4][3]) {
    rgb565(a, p[0]); rgb565(b, p[1]);
    for (int k = 0; k < 3; ++k) {
        p[2][k] = a > b ? (2*p[0][k]+p[1][k])/3 : (p[0][k]+p[1][k])/2;
        p[3][k] = a > b ? (p[0][k]+2*p[1][k])/3 : 0;
    }
}

static void decode(const unsigned char *b, unsigned char p[16][3]) {
    unsigned char pal[4][3];
    palette(u16(b), u16(b+2), pal);
    uint32_t bits; memcpy(&bits, b+4, 4);
    for (int i=0;i<16;++i) memcpy(p[i], pal[(bits>>(2*i))&3], 3);
}

static void encode(unsigned char p[16][3], unsigned char *out) {
    unsigned char lo[3]={255,255,255}, hi[3]={0,0,0};
    for (int i=0;i<16;++i) for(int k=0;k<3;++k) {
        if(p[i][k]<lo[k]) lo[k]=p[i][k];
        if(p[i][k]>hi[k]) hi[k]=p[i][k];
    }
    uint16_t a=to565(hi), b=to565(lo);
    if(a<b) { uint16_t t=a; a=b; b=t; }
    if(a==b) { if(a<65535) ++a; else --b; }
    unsigned char pal[4][3]; palette(a,b,pal);
    uint32_t bits=0;
    for(int i=0;i<16;++i) {
        int best=0, err=2147483647;
        for(int j=0;j<4;++j) {
            int e=0;
            for(int k=0;k<3;++k) {int d=(int)p[i][k]-pal[j][k];e+=d*d;}
            if(e<err){err=e;best=j;}
        }
        bits|=(uint32_t)best<<(2*i);
    }
    memcpy(out,&a,2);memcpy(out+2,&b,2);memcpy(out+4,&bits,4);
}

static int inside(float x,float y,Rect r){return x>=r.x0&&x<r.x1&&y>=r.y0&&y<r.y1;}

static int pants_pixel(const unsigned char *c) {
    return c[0]<70&&c[1]<80&&c[2]>12&&c[2]<120&&c[2]>c[0]*1.30f&&c[2]>c[1]*1.20f;
}

static int cloth_pixel(const unsigned char *c) {
    return c[0]>45&&c[1]>65&&c[2]>85&&c[1]>c[0]*1.07f&&c[2]>c[0]*1.20f;
}

int main(int argc, char **argv) {
    if(argc!=4) fail("Usage: recolor_assets job.bin original.ubulk output.ubulk");
    FILE *f=fopen(argv[1],"rb");if(!f)fail("Cannot open job");
    if(r32(f)!=0x31504342)fail("Invalid job");
    uint32_t mode=r32(f),width=r32(f),height=r32(f),nrect=r32(f);
    if(mode>3||width>8192||height>8192||nrect>32)fail("Invalid dimensions");
    Rect rects[32];rd(f,rects,nrect*sizeof(Rect));
    uint32_t nmips=r32(f);if(nmips>16)fail("Too many mips");
    Mip mips[16];
    for(unsigned i=0;i<nmips;++i){
        mips[i].w=r32(f);mips[i].h=r32(f);mips[i].count=r32(f);
        mips[i].tiles=calloc(mips[i].count,sizeof(Tile));
        for(unsigned j=0;j<mips[i].count;++j){
            mips[i].tiles[j].x=r32(f);mips[i].tiles[j].y=r32(f);mips[i].tiles[j].offset=r64(f);
        }
    }
    unsigned char *chiefmask=NULL;
    if(mode==3){chiefmask=malloc((size_t)width*height);if(!chiefmask)fail("Out of memory");rd(f,chiefmask,(size_t)width*height);}
    fclose(f);
    f=fopen(argv[2],"rb");if(!f)fail("Cannot open bulk data");
    fseek(f,0,SEEK_END);size_t length=ftell(f);rewind(f);
    unsigned char *bulk=malloc(length);if(!bulk)fail("Out of memory");rd(f,bulk,length);fclose(f);
    size_t samples=(size_t)width*height*3;
    unsigned char *base=calloc(samples,1);
    float *delta=calloc(samples,sizeof(float));
    if(!base||!delta)fail("Out of memory");
    for(unsigned i=0;i<mips[0].count;++i){
        Tile t=mips[0].tiles[i];if(t.offset+9248>length)fail("Invalid tile offset");
        for(int by=1;by<33;++by)for(int bx=1;bx<33;++bx){
            unsigned char p[16][3];decode(bulk+t.offset+(by*34+bx)*8,p);
            for(int py=0;py<4;++py)for(int px=0;px<4;++px){
                unsigned x=t.x*128+(bx-1)*4+px,y=t.y*128+(by-1)*4+py;
                if(x<width&&y<height)memcpy(base+((size_t)y*width+x)*3,p[py*4+px],3);
            }
        }
    }
    unsigned char *cloth=calloc((size_t)width*height,1);
    if(!cloth)fail("Out of memory");
    if(mode==0){
        unsigned char *seen=calloc((size_t)width*height,1);
        uint32_t *queue=malloc((size_t)width*height*sizeof(uint32_t));
        if(!seen||!queue)fail("Out of memory");
        for(uint32_t start=0;start<width*height;++start){
            if(seen[start]||!cloth_pixel(base+(size_t)start*3))continue;
            size_t head=0,tail=1;queue[0]=start;seen[start]=1;
            while(head<tail){
                uint32_t p=queue[head++],x=p%width,y=p/width;
                uint32_t neighbours[4]={x?p-1:p,x+1<width?p+1:p,y?p-width:p,y+1<height?p+width:p};
                for(int j=0;j<4;++j){
                    uint32_t q=neighbours[j];
                    if(!seen[q]&&cloth_pixel(base+(size_t)q*3)){seen[q]=1;queue[tail++]=q;}
                }
            }
            if(tail>20000)for(size_t j=0;j<tail;++j)cloth[queue[j]]=1;
        }
        memset(seen,0,(size_t)width*height);
        for(uint32_t start=0;start<width*height;++start){
            if(seen[start]||!pants_pixel(base+(size_t)start*3))continue;
            size_t head=0,tail=1;queue[0]=start;seen[start]=1;
            uint64_t sumx=0;uint32_t maxy=0;
            while(head<tail){
                uint32_t p=queue[head++],x=p%width,y=p/width;
                sumx+=x;if(y>maxy)maxy=y;
                uint32_t neighbours[4]={x?p-1:p,x+1<width?p+1:p,y?p-width:p,y+1<height?p+width:p};
                for(int j=0;j<4;++j){
                    uint32_t q=neighbours[j];
                    if(!seen[q]&&pants_pixel(base+(size_t)q*3)){seen[q]=1;queue[tail++]=q;}
                }
            }
            if(tail>20000&&sumx/(double)tail>width*.5&&maxy>height*.8)
                for(size_t j=0;j<tail;++j)cloth[queue[j]]=2;
        }
        free(seen);free(queue);
    }
    size_t changed_pixels=0;
    for(unsigned y=0;y<height;++y)for(unsigned x=0;x<width;++x){
        size_t at=((size_t)y*width+x)*3;
        unsigned char *c=base+at;float u=(x+.5f)/width,v=(y+.5f)/height;
        int selected=0;for(unsigned j=0;j<nrect;++j)if(inside(u,v,rects[j]))selected=1;
        float l=.2126f*c[0]+.7152f*c[1]+.0722f*c[2];
        float out=l;int modify=0;
        if(mode==0){
            if(cloth[(size_t)y*width+x]){
                out=cloth[(size_t)y*width+x]==2 ? 12.f+l*.35f : 10.f+l*.085f;modify=1;
            }
        }else if(mode>=2){
            unsigned char region=mode==2?1:chiefmask[(size_t)y*width+x];
            if(pants_pixel(c)&&(region==1||region==2)){
                out=region==1?fminf(245.f,205.f+l*.9f):12.f+l*.35f;modify=1;
            }
        }else{
            if(selected){
                float ink=1.f-fminf(1.f,fmaxf(0.f,(l-65.f)/95.f));
                out=(18.f+l*.04f)*(1.f-ink)+230.f*ink;modify=1;
            }else if(l>85.f){out=18.f+l*.04f;modify=1;}
        }
        if(modify){
            ++changed_pixels;
            for(int k=0;k<3;++k)delta[at+k]=out-c[k];
        }
    }
    free(base);free(cloth);free(chiefmask);
    size_t blocks=0;
    for(unsigned m=0;m<nmips;++m){
        unsigned w=mips[m].w,h=mips[m].h;
        for(unsigned i=0;i<mips[m].count;++i){
            Tile t=mips[m].tiles[i];if(t.offset+9248>length)fail("Invalid tile offset");
            for(int by=0;by<34;++by)for(int bx=0;bx<34;++bx){
                unsigned char *block=bulk+t.offset+(by*34+bx)*8;
                unsigned char p[16][3];decode(block,p);int dirty=0;
                if((mode==0||mode==3)&&m==0){
                    int gold=0;
                    for(int q=0;q<16;++q)if(p[q][0]>140&&p[q][1]>80&&p[q][2]<p[q][0]*.7f)gold=1;
                    if(gold)continue;
                }
                for(int py=0;py<4;++py)for(int px=0;px<4;++px){
                    int x=wrap((int)t.x*128+bx*4+px-4,w),y=wrap((int)t.y*128+by*4+py-4,h);
                    size_t at=((size_t)y*w+x)*3;
                    for(int k=0;k<3;++k){
                        int old=p[py*4+px][k];
                        int now=clampi((int)lroundf(old+delta[at+k]),0,255);
                        p[py*4+px][k]=now;if(now!=old)dirty=1;
                    }
                }
                if(dirty){encode(p,block);++blocks;}
            }
        }
        if(m+1<nmips){
            unsigned nw=mips[m+1].w,nh=mips[m+1].h;
            float *next=calloc((size_t)nw*nh*3,sizeof(float));if(!next)fail("Out of memory");
            for(unsigned y=0;y<nh;++y)for(unsigned x=0;x<nw;++x)for(int k=0;k<3;++k){
                float sum=0;
                for(int dy=0;dy<2;++dy)for(int dx=0;dx<2;++dx){
                    unsigned xx=clampi(x*2+dx,0,w-1),yy=clampi(y*2+dy,0,h-1);
                    sum+=delta[((size_t)yy*w+xx)*3+k];
                }
                next[((size_t)y*nw+x)*3+k]=sum*.25f;
            }
            free(delta);delta=next;
        }
    }
    free(delta);
    f=fopen(argv[3],"wb");if(!f)fail("Cannot write output");
    if(fwrite(bulk,1,length,f)!=length)fail("Cannot write all output");
    fclose(f);
    free(bulk);for(unsigned m=0;m<nmips;++m)free(mips[m].tiles);
    printf("{\"changed_pixels\":%zu,\"changed_blocks\":%zu,\"bytes\":%zu}\n",changed_pixels,blocks,length);
    return 0;
}
