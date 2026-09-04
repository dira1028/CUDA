# 컴파일러 설정
CC = gcc
CXX = g++

# 최적화 및 경고 옵션
CFLAGS = -O3 -Wall
# Windows/Linux GCC 모두 MSVC 전용 보안 함수가 없으므로 표준 함수 치환 매크로 적용
CXXFLAGS = -O3 -Wall -D"fopen_s(fp,fmt,mode)=(*(fp)=fopen(fmt,mode))" -D"fprintf_s=fprintf"

# OS 자동 감지 및 환경별 변수 설정
ifeq ($(OS),Windows_NT)
	# Windows 환경 (MinGW/cmd 호환)
	TARGET = mldsa_time_test.exe
	CLEAN_CMD = del /Q *.o $(TARGET) 2>nul || rm -f *.o $(TARGET)
else
	# Linux 환경
	TARGET = mldsa_time_test
	CLEAN_CMD = rm -f *.o $(TARGET)
endif

# 순수 C 소스 파일 (GCC로 컴파일)
C_SRCS = fips202.c ntt.c packing.c poly.c polyvec.c randombytes.c reduce.c rounding.c symmetric-shake.c
C_OBJS = $(C_SRCS:.c=.o)

# C++ 소스 파일 (G++로 컴파일, 확장자를 변경한 operation_time.cpp 포함)
CXX_SRCS = DS_timer.cpp operation_time.cpp
CXX_OBJS = $(CXX_SRCS:.cpp=.o)

# 기본 빌드 타겟
all: $(TARGET)

# 최종 실행 파일 링킹 (C++ 링커 사용)
$(TARGET): $(C_OBJS) $(CXX_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

# 순수 C 객체 파일 생성 규칙
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# C++ 객체 파일 생성 규칙
%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

# 빌드 잔여물 정리
clean:
	$(CLEAN_CMD)