#include "MotionTextEngine.h"
#include <iostream>
#include <string>
#include <cstdlib>

static void MTE_CALL progress(int p,void*) { std::cout<<"\rProgress: "<<p<<"%"<<std::flush; }
int wmain(int argc,wchar_t** argv) {
    if(argc<10) {
        std::wcerr<<L"Usage: MotionText.exe <file|rtsp|udp|capture> <source> <output> <target_text> <x> <y> <w> <h> <live|movie>\n";
        return 2;
    }
    int type=0;
    std::wstring st=argv[1];
    if(st==L"rtsp") type=MTE_SOURCE_RTSP;
    else if(st==L"udp") type=MTE_SOURCE_UDP;
    else if(st==L"capture") type=MTE_SOURCE_CAPTURE_DEVICE;
    else if(st!=L"file") { std::wcerr<<L"Unknown source type\n"; return 2; }
    MTE_Rect r{_wtoi(argv[5]),_wtoi(argv[6]),_wtoi(argv[7]),_wtoi(argv[8])};
    int mode=std::wstring(argv[9])==L"movie"?MTE_MODE_MOVIE_QUALITY:MTE_MODE_LIVE_BALANCED;
    MTE_Config c{mode,5,3,100,12,0,1,3,700,2,160,0.58f,8,8,0,65};
    int rc=MTE_Process(type,argv[2],argv[3],r,argv[4],&c,progress,nullptr);
    std::wcout<<L"\n";
    if(rc) std::wcerr<<L"MotionTextEngine error "<<rc<<L": "<<MTE_LastError()<<L"\n";
    return rc?1:0;
}
