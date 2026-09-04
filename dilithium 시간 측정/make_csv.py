import pandas as pd
import re

keygen_ops, keygen_times = [], []
sign_ops, sign_times = [], []
verify_ops, verify_times = [], []

# 현재 어떤 단계의 로그를 읽고 있는지 구분하기 위한 카운터
phase_counter = 0

with open('data.txt', 'r', encoding='utf-8') as f:
    for line in f:
        # '**** Timer report ****'가 등장할 때마다 단계를 1씩 증가시킴
        if "**** Timer report ****" in line:
            phase_counter += 1
            continue
        
        match = re.match(r'\s*(.+?)\s*:\s*([\d.]+)\s*ms', line)
        if match:
            op = match.group(1).strip()
            time_val = float(match.group(2))
            
            # 첫 번째 등장: Keygen
            if phase_counter == 1:
                keygen_ops.append(op)
                keygen_times.append(time_val)
            # 두 번째 등장: Sign
            elif phase_counter == 2:
                sign_ops.append(op)
                sign_times.append(time_val)
            # 세 번째 등장: Verify
            elif phase_counter == 3:
                verify_ops.append(op)
                verify_times.append(time_val)

# 각 단계 사이에 넣을 4칸의 빈 열
empty_cols = ['', '', '', '']
empty_times = ['', '', '', '']

# 가로 배치 형태 구성 (Keygen -> 4칸 공백 -> Sign -> 4칸 공백 -> Verify)
headers = keygen_ops + empty_cols + sign_ops + empty_cols + verify_ops
times = keygen_times + empty_times + sign_times + empty_times + verify_times

df = pd.DataFrame([times], columns=headers)

df.to_csv('timing_horizontal_pandas.csv', index=False, encoding='utf-8-sig')
print("CSV 파일이 성공적으로 생성되었습니다.")