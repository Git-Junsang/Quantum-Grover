from pathlib import Path
from collections import Counter
import json, re, sys

ROOT = Path(__file__).parent
EDITS = {}
def add(name, rule, old, new):
    EDITS.setdefault(name, []).append({'rule':rule, 'before':old, 'after':new})

n='01_qubits_and_states'
add(n,'D-14','이 장이 이 해설서 전체의 출발점이며, 여기서 다지는 직관 위에','이 장은 이 해설서의 출발점입니다. 여기서 익힌 개념을 바탕으로')
add(n,'D-14','의 Grover가 세워집니다.','의 Grover를 배웁니다.')
add(n,'D-8','핵심은 이것입니다: bit의 state는','bit의 state는')
add(n,'A-7','qubit도 state를 가집니다.','qubit에도 state가 있습니다.')
add(n,'D-14','이 vector가 사는 공간을','이 vector가 속한 공간을')
add(n,'D-2','인 어엿한 unit vector입니다.','인 unit vector입니다.')
add(n,'D-14','라는 풍부한 대상을 가리키듯,','를 가리키듯,')
add(n,'C-11','qubit가 흥미로운 이유는,','qubit가 흥미로운 이유는')
add(n,'D-2','다음은 완벽하게 정당한 qubit state입니다:','다음도 가능한 qubit state입니다:')
add(n,'D-2','하지만 여기에 큰 함정이 있습니다.','다만 이 표현은 오해하기 쉽습니다.')
add(n,'D-14','"이 qubit가 몰래 0이거나 1인데 우리가 모르는 것"이 아닙니다.','"qubit가 이미 0 또는 1로 정해져 있는데 우리가 그 값을 모르는 상태"를 뜻하지 않습니다.')
add(n,'D-2','에서 결정적으로 드러납니다.','에서 드러납니다.')
add(n,'A-18','에서 완전히 밝혀지지만, 미리 말하면:','에서 설명하겠지만, 미리 살펴보면')
add(n,'D-14','normalization이 묶는 것은 gate를 **끝낸 뒤**의 state이지, gate를 계산하는 **도중**에 스쳐 가는 중간값까지는 아닙니다.','normalization은 gate를 **끝낸 뒤**의 state가 만족해야 하는 조건이며, gate를 계산하는 **도중**의 중간값에까지 적용되는 조건은 아닙니다.')
add(n,'D-14','[7장 phase kickback](07_oracle_and_phase_kickback.md)의 무대가 됩니다.','[7장 phase kickback](07_oracle_and_phase_kickback.md)을 이해하는 바탕이 됩니다.')
add(n,'D-2','**놀랍게도 불가능합니다.**','**불가능합니다.**')
add(n,'D-14','FPGA emulator는 이 금지에서 자유롭습니다 — amplitude가 BRAM에 숫자로 적혀 있으니 열어 보면 다 보이니까요.','FPGA emulator에서는 이 제약이 없습니다 — amplitude가 BRAM에 숫자로 저장되어 있어 값을 직접 읽을 수 있기 때문입니다.')
add(n,'D-8','우리가 기억할 것은 이것뿐입니다:','다음 정의를 기억해 두세요:')
add(n,'D-14','그 vector가 사는 곳이','그 vector가 속한 곳이')
add(n,'C-11','qubit의 물리를 흉내 내는 것이 아니라,','qubit의 물리를 흉내 내는 것이 아니라')
add(n,'A-18','칸 수가 power of 2라서 mean도 arithmetic shift로 끝나므로,','칸 수가 power of 2라서 mean도 arithmetic shift로 구할 수 있으므로')
add(n,'D-14','Grover가 지나는 state에서만은','Grover가 계산하는 state에서는')

n='04_measurement'
add(n,'D-14','계산하는 emulator에서는 유혹이 하나 생깁니다.','계산하는 emulator에서는 다른 방법을 생각해 볼 수 있습니다.')
add(n,'D-14','amplitude가 전부 눈앞에 있으니,','amplitude를 전부 읽을 수 있으니')
add(n,'D-14','probability이니 sample이니 하는 것을 circuit으로 만들 필요도 없어 보입니다.','probability에 따라 sample을 뽑는 과정을 circuit으로 만들 필요도 없어 보입니다.')
add(n,'D-14','"높은 probability로 solution을 준다"는 quantum algorithm의 약속이 여기서 소리 없이 사라집니다.','이렇게 하면 "높은 probability로 solution을 준다"는 quantum algorithm의 동작을 재현하지 못합니다.')
add(n,'D-14','**정확히 같은 값**으로 나란히 자랍니다.','**정확히 같은 값**을 유지하며 커집니다.')
add(n,'A-18','predicate를 만족하는 element를 전부 enumeration해야 하는 우리 accelerator에게는 치명적이고, 그래서','predicate를 만족하는 element를 전부 enumeration해야 하는 우리 accelerator에서는 이 방식으로 목적을 달성할 수 없습니다. 그래서')
add(n,'D-8','규칙을 지키려면 규칙대로 뽑아야 합니다. 진짜 quantum 장치에서는 자연이 이 sampling을 공짜로 해 주지만, emulator에서는 우리가 circuit으로 만들어야 합니다.','진짜 quantum 장치에서는 물리적 과정으로 이 sampling이 이루어지지만, emulator에서는 우리가 circuit으로 만들어야 합니다.')
add(n,'D-14','random number $r$ 을 하나 떨어뜨린 뒤,','random number $r$ 을 하나 뽑은 뒤')
add(n,'C-11','그 interval의 길이가 바로 $|a_i|^2$ 이므로,','그 interval의 길이가 바로 $|a_i|^2$ 이므로')
add(n,'D-8','여기서 hardware 설계에 두고두고 쓰이는 성질이 하나 나옵니다.','이 방법에는 hardware 설계에 유용한 성질이 있습니다.')
add(n,'D-14','순서를 마음대로 바꿔도 된다는 이 자유 덕분에','훑는 순서를 바꿀 수 있으므로')
add(n,'D-14','실기 quantum이 할 수 있는 만큼만 하도록 circuit을 스스로 묶어 두려는 것입니다','실기 quantum에서 가능한 동작만 circuit으로 재현하려는 것입니다')
add(n,'D-14','measurement의 가장 중요한 성질: **measurement는 state를 가만두지 않습니다.**','measurement의 가장 중요한 성질: **measurement는 state를 바꿉니다.**')
add(n,'D-2','그리고 결정적으로, collapse 후에는','collapse 후에는')
add(n,'D-14','shot을 여러 번 던져 가며 더듬어야 합니다.','shot을 여러 번 실행하며 답을 찾아야 합니다.')
add(n,'D-14','shot을 몇 번 어떻게 던질지 정하는','shot을 몇 번 어떻게 실행할지 정하는')
add(n,'D-14','방금까지 애써 키워 놓은 amplitude가 그 자리에서 사라지고','방금까지 키워 놓은 amplitude가 사라지고')
add(n,'D-14','그 뿌리는 "emulator의 measurement는 읽기 전용"이라는 이 한 줄입니다.','이는 "emulator의 measurement는 읽기 전용"이라는 성질을 이용한 것입니다.')
add(n,'D-14','실기 quantum은 흉내조차 낼 수 없는 일이라 공짜로 얻은 이득처럼 보이는데, 정말 공짜인지 — 결과가 달라지지는 않는지 — 는 따로 따져야 할 문제입니다','실기 quantum에서는 할 수 없는 일이므로, 이런 재활용으로 계산 결과가 달라지지는 않는지 따로 확인해야 합니다')
add(n,'D-14','condition은 곧 "measurement probability의 sum이 1"이라는 자명한 요구입니다.','condition은 곧 "measurement probability의 sum이 1"이라는 조건입니다.')
add(n,'D-14','dimension이 $2^{\text{number of qubits}}$ 인 state space가 열리고,','dimension이 $2^{\text{number of qubits}}$ 인 state space를 다루고')

n='07_oracle_and_phase_kickback'
add(n,'D-14','이제 algorithm의 세계로 들어갑니다.','이제 algorithm을 살펴봅니다.')
add(n,'D-14','함숫값을 amplitude의 **sign**으로 바꿔치기하는 마법입니다.','함숫값을 amplitude의 **sign**에 반영하는 방법입니다.')
add(n,'D-14','를 떠받치는 기둥입니다.','를 이해하는 바탕입니다.')
add(n,'D-2','는 말이 완전히 명확해집니다.','는 말의 의미를 알 수 있습니다.')
add(n,'D-8','핵심은 우리가 function **내부 동작은 모른다**는 것입니다.','우리는 function의 **내부 동작은 모른다**고 가정합니다.')
add(n,'D-8','이제 문제는 이 sign이 **measurement만으로는 드러나지 않는다**는 것입니다.','다만 이 sign은 **measurement만으로는 드러나지 않습니다.**')
add(n,'D-14','표식은 붙었으되 그냥 measurement만 해서는 아직 보이지 않는 것이죠.','표식이 붙어도 measurement 결과에는 아직 차이가 없는 것이죠.')
add(n,'D-8','가장 중요한 부분입니다. oracle을','oracle을')
add(n,'D-14','로 두면, 마법처럼 **형태 B(phase oracle)** 가 튀어나옵니다.','로 두면 **형태 B(phase oracle)** 와 같은 동작을 얻습니다.')
add(n,'D-14','출력 qubit에서 일어나야 할 변화가 입력 qubit의 phase로 되차인 것입니다.','출력 qubit에 가하는 연산의 효과가 입력 qubit의 phase 변화로 나타난 것입니다.')
add(n,'D-14','곁다리(constant)로 남으므로,','변하지 않은 상태(constant)로 남으므로')
add(n,'D-14','관찰 하나를 미리 챙겨 두면 나중에 크게 씁니다.','성질 하나를 미리 살펴두겠습니다.')
add(n,'D-14','어느 항도 특별대우를 받지 않고','어느 항도 따로 구별하지 않고')
add(n,'D-14','solution이 여럿일 때 무너지는 뿌리가 바로 이 대칭성입니다.','solution이 여럿일 때 실패하는 이유가 바로 이 대칭성입니다.')
add(n,'D-14','이와 쌍둥이인','이와 짝을 이루는')
add(n,'D-14','이것은 **판정 function','이는 **판정 function')
add(n,'D-14','대상은 미리 못 박아 둔 solution index가 아니라','대상은 미리 정해 둔 solution index가 아니라')
add(n,'D-14','대신 대가도 이 장의 정의에서 그대로 따라옵니다 —','이 장의 정의에 따른 제약도 있습니다 —')
add(n,'D-14','쌍둥이 diffusion operator와 함께','diffusion operator와 짝을 이루어')
add(n,'D-14','가 어떻게 협력해 classical computer를 압도하는지, 완전한 계산으로 확인합니다.','를 이용하면 classical computer보다 적은 질의로 답을 얻는 과정을 전체 계산으로 확인합니다.')

n='10_glossary_and_cheat_sheet'
add(n,'C-8','이 장은 새로운 내용을 배우는 곳이 아니라, 1~9장의 핵심을 **한눈에** 모은 참조 자료입니다.','이 장은 1~9장의 핵심을 **한눈에** 모은 참조 자료입니다.')
add(n,'D-8','값어치는 속도 우위가 아니라 quantum algorithm의 동작을 **결정적이고 재현 가능하게 재현·검증하는 전용 hardware**라는 데 있습니다','이 장치의 목적은 속도 우위를 얻는 데 있지 않습니다. quantum algorithm의 동작을 **결정적이고 재현 가능하게 재현·검증하는 전용 hardware**입니다')
add(n,'D-14','이 project가 실제로 밟은 함정','이 project에서 실제로 겪은 문제')
add(n,'D-14','solution이 둘 이상일 때 동률로 무너지는 것을 확인하고 Born-rule sampling으로 갈아엎었고','solution이 둘 이상일 때 동률 때문에 실패하는 것을 확인하고 Born-rule sampling으로 바꾸었습니다')
add(n,'A-18',')), amplitude의 크기만 보고 integer bits를 sign 1-bit로 잡았다가',')). 또 amplitude의 크기만 보고 integer bits를 sign 1-bit로 잡았다가')
add(n,'A-18','한때 integer bits를 2 bits로 늘렸고, 최종 RTL은','한때 integer bits를 2 bits로 늘렸습니다. 최종 RTL은')
add(n,'D-14','11장부터 18장까지 여덟 장이 그 이야기이고, 이 project가 실제로 만들려는 물건입니다.','11장부터 18장까지 여덟 장에서 이 project가 실제로 만들려는 장치를 다룹니다.')
add(n,'D-14','Part 5(11·12장)가 뼈대 — memory 지도와 수 표현 — 를 놓고,','Part 5(11·12장)가 기초가 되는 memory 지도와 수 표현을 설명하고')
add(n,'D-14','accumulation·shift·subtraction만으로 닫히는 diffusion operator','accumulation·shift·subtraction만으로 계산하는 diffusion operator')
add(n,'D-14','host와는 UART로 말합니다.','host와는 UART로 통신합니다.')
add(n,'D-14','읽는 도중 link를 따라가지 않아도 되게 하려는 배려일 뿐이고, 값이 어긋나면 그쪽이 기준입니다.','읽는 도중 link를 따라가지 않고도 확인할 수 있게 하기 위해서입니다. 값이 어긋나면 설계 결정표를 기준으로 합니다.')

n='13_oracle_diffusion_measurement_datapath'
add(n,'D-14','Q1.22 fixed-point로 못 박았습니다.','Q1.22 fixed-point로 정했습니다.')
add(n,'D-8','이 장이 심으려는 감각은 하나입니다 —','이 장에서 확인할 성질은 다음과 같습니다 —')
add(n,'D-14','9장에서 inversion about the mean이 우아하다고 느꼈다면, 그 우아함의 정체가 여기서 드러납니다.','9장에서 배운 inversion about the mean이 어떤 연산으로 구현되는지 살펴보겠습니다.')
add(n,'D-14','"0 multipliers"는 경로를 붙이지 않으면 거짓말이 되는 문장이기 때문입니다.','"0 multipliers"라고만 쓰면 어느 경로를 가리키는지 알 수 없어 부정확하기 때문입니다.')
add(n,'D-14','여기에 pipeline을 채우고 비우는 몇 cycle이 붙어,','여기에 pipeline을 채우고 비우는 몇 cycle이 더해져')
add(n,'D-14','constant가 필요 없으니 RTL은 이 값을 `grover_param.vh` 의 integer 하나로 굽습니다.','constant가 필요 없으니 RTL은 이 값을 `grover_param.vh` 의 integer 하나로 정의합니다.')
add(n,'D-14','짝수일 때는 이 비용을 치르지 않습니다 — 작지만 기분 좋은 이득입니다.','짝수일 때는 이 오차가 생기지 않습니다.')
add(n,'D-8','여기서 원문을 그대로 베끼면 안 되는 지점이 하나 있습니다.','다만 원문의 값을 그대로 옮겨 쓰면 안 됩니다.')
add(n,'D-14','위에서 32768을 손으로 유도한 것이 그 실천입니다.','위의 32768도 직접 계산해 유도한 값입니다.')
add(n,'D-14','최적 number of iterations를 고정 constant로 굽지 않기 때문에','최적 number of iterations를 고정 constant로 정의하지 않기 때문에')
add(n,'D-8','이 절이 이 project의 주제 그 자체입니다. oracle은','이 project의 oracle은')
add(n,'D-14','순진하게 접근하면 comparator IP 네 개를 부르고 싶어집니다. 그럴 필요가 없습니다.','조건마다 comparator IP를 하나씩 두는 방법을 먼저 생각할 수 있지만, 네 개가 모두 필요하지는 않습니다.')
add(n,'D-14','17 bits로 넓히는 이 한 줄이 없으면 circuit이 조용히 틀립니다.','17 bits로 넓히지 않으면 circuit이 잘못된 결과를 냅니다.')
add(n,'D-14','`GT` 가 공짜라는 점을 눈여겨보십시오.','`GT` 는 추가 비교 연산이 필요 없다는 점을 눈여겨보십시오.')
add(n,'D-14','판정 앞에는 문이 하나 더 있습니다.','판정 앞에는 조건이 하나 더 있습니다.')
add(n,'D-14','이 문이 없으면 지난 실험의 쓰레기 값이 solution 행세를 합니다.','이 조건이 없으면 지난 실험에서 남은 값이 solution으로 판정될 수 있습니다.')
add(n,'D-14','solution index를 parameter로 못 박고','solution index를 parameter로 고정하고')
add(n,'D-14','다만 그것은 verification용 발판이지 설계가 아닙니다.','다만 그것은 verification을 위한 중간 단계이며 실제 설계는 아닙니다.')
add(n,'D-14','판정이 끝나면 뒷단은 허무할 만큼 간단합니다.','판정 뒤의 연산은 간단합니다.')
add(n,'D-14','이 말한 역설의 가장 선명한 사례입니다.','에서 설명한 차이를 잘 보여 주는 사례입니다.')
add(n,'D-14','sign 반전이 항등이 되고, 그 칸에 대해 oracle이 조용히 무력화됩니다.','sign 반전이 항등이 되어 그 칸에서는 oracle이 작동하지 않습니다.')
add(n,'D-8','그 지점을 못 박아 둡니다. 한 번의','그 지점을 확인해 두겠습니다. 한 번의')
add(n,'D-14','분할됩니다. 지금 array에 실려 있는 state','분할됩니다. 지금 array에 저장된 state')
add(n,'D-14','array에 실려 있는 state','array에 저장된 state')
add(n,'D-14','fraction bits가 깎이는 곳은','fraction bits가 줄어드는 곳은')
add(n,'D-14','결과는 diffusion operator도 아니고 아무것도 아닌 값이 됩니다.','결과는 diffusion operator의 계산과 달라집니다.')
add(n,'D-14','amplitude가 대놓고 틀립니다','amplitude의 오차가 뚜렷합니다')
add(n,'D-14','Q1.22의 천장을 넘을 수 있습니다.','Q1.22의 표현 범위를 넘을 수 있습니다.')
add(n,'D-14','둘째 — 이쪽이 실제로 물립니다 — float64 model과 대조할 때,','둘째, float64 model과 대조할 때는')
add(n,'D-8','이제 이 장 첫머리의 약속을 정확한 문장으로 닫습니다.','이제 이 장에서 설명한 연산 경로를 정리합니다.')
add(n,'D-14','multiplier·divider를 물어옵니다.','multiplier·divider가 생성될 수 있습니다.')
add(n,'D-14','최대값을 고르는 방식이 원리적으로 무너진다는 사실','최대값을 고르는 방식이 원리적으로 실패한다는 사실')
add(n,'D-14','maximum을 고르는 방식이 원리적으로 무너진다는 사실','maximum을 고르는 방식이 원리적으로 실패한다는 사실')

n='16_iteration_control_and_checkpoints'
add(n,'D-14','**여러 번 던져야** 하고,','**여러 번 실행해야** 하고')
add(n,'D-14','이 project가 기존 Grover emulator들과 갈라지는 지점이 바로 여기이고,','이 점이 이 project와 기존 Grover emulator들의 차이이며')
add(n,'D-14','9.6절에서 못 박았듯','9.6절에서 확인했듯')
add(n,'D-14','quantum algorithm 쪽에는 정석 처방이 있습니다.','quantum algorithm에는 이 문제를 다루는 표준 방법이 있습니다.')
add(n,'D-14','13장의 multiplier 없는 산술이 통째로 무너집니다.','13장의 multiplier 없는 산술을 그대로 쓸 수 없게 됩니다.')
add(n,'D-14','counting 하나를 위해 accelerator 전체를 complex number로 바꾸는 거래는 남는 장사가 아닙니다.','counting을 위해 accelerator 전체를 complex number로 바꾸는 것은 비용에 비해 이득이 작습니다.')
add(n,'D-8','여기서 정직하게 짚고 갈 것이 하나 있습니다.','여기서 구분해 둘 점이 있습니다.')
add(n,'D-14','solution을 미리 세어 놓고 시작하는 것은 amplitude array를 훔쳐보는 것과 같은 반칙이고, 그렇게 만든 기계는 "Grover를 돌리는 기계"가 아니라 "Grover처럼 생긴 무언가"가 됩니다.','solution을 미리 세어 놓고 시작하는 것은 amplitude array를 직접 읽는 것과 마찬가지로 실제 장치에서 얻을 수 없는 정보를 쓰는 일입니다. 그렇게 만든 기계는 Grover의 외형만 따를 뿐 Grover의 동작을 충실히 재현하지 못합니다.')
add(n,'D-14','충실도가 속도를 이깁니다.','속도보다 충실도를 우선합니다.')
add(n,'D-8','답은 success probability의 모양에 있습니다.','success probability의 모양을 보면 이유를 알 수 있습니다.')
add(n,'D-14','그 shot은 몇 번을 반복해도 영원히 실패합니다.','그 shot은 몇 번을 반복해도 실패합니다.')
add(n,'D-14','algorithm의 정당성을 떠받치는 요소입니다.','algorithm의 정당성을 보장하는 요소입니다.')
add(n,'D-14','shot을 더 많이 던져야 하고,','shot을 더 많이 실행해야 하고')
add(n,'D-14','상한이 overshoot를 막는 장치로 일하는 모습입니다.','이렇게 상한이 overshoot를 막습니다.')
add(n,'D-14','**28항 ROM**에 구워 둡니다','**28항 ROM**에 저장해 둡니다')
add(n,'D-14','승부가 나기 시작하는 것은','실제로 답을 얻기 쉬워지는 것은')
add(n,'D-14','각각 18% 넘게 더 벌었습니다','각각 18% 넘게 더 줄였습니다')
add(n,'D-14','measurement가 뱉은 후보 index','measurement가 내놓은 후보 index')
add(n,'D-14','**non-solution을 뱉을 수 있기**','**non-solution을 내놓을 수 있기**')
add(n,'D-14','shot 사이의 state는 전부 hardware가 쥡니다.','shot 사이의 state는 전부 hardware가 관리합니다.')
add(n,'D-8','이제 이 장의 본론입니다. 22.7번의 shot 가운데','22.7번의 shot 가운데')
add(n,'D-14','amplitude에 **한 글자도 쓰지 않습니다.**','amplitude에 **아무 값도 쓰지 않습니다.**')
add(n,'A-7','최대 세 벌(a Checkpoint-Capacity of 3) 들고 있고,','최대 세 벌(a Checkpoint-Capacity of 3) 저장하고')
add(n,'D-14','중간 state를 다른 checkpoint slot에 떨궈 두는 것도 거의 공짜입니다.','중간 state를 다른 checkpoint slot에 저장하는 데도 추가 비용이 거의 들지 않습니다.')
add(n,'D-14','진짜 LFSR state를 건드리지 않고 사본을 굴려','실제 LFSR state를 바꾸지 않고 사본을 전진시켜')
add(n,'D-14','정해진 정렬 순서로 동률을 끊어','정해진 정렬 순서로 동률을 처리해')
add(n,'D-8','이 절이 이 장에서 가장 중요합니다. 실패한 shot의','실패한 shot의')
add(n,'D-14','다만 정직하게 덧붙일 것이 있습니다.','다만 제약도 있습니다.')
add(n,'D-14','quantum mechanics가 그것을 허락해서가 아닙니다.','quantum mechanics에서 가능한 동작이어서가 아닙니다.')
add(n,'D-2','가장 극적인 사례입니다.','대표적인 사례입니다.')
add(n,'D-14','쓰면 거짓말이 됩니다 —','쓰면 부정확합니다 —')
add(n,'D-14','software에 맡기면 **반드시 새는 곳이 생깁니다.**','software에 맡기면 **무효화 처리를 빠뜨리는 경우가 반드시 생깁니다.**')
add(n,'D-14','낡은 amplitude 위에 새 oracle이 얹혀','이전 amplitude에 새 oracle이 적용되어')
add(n,'D-14','설정값에서 공짜로 판정되는데','설정값에서 추가 비용 없이 판정할 수 있는데')
add(n,'D-14','추가 memory가 0이라는 매력이 있었지만,','추가 memory가 0이라는 이점이 있었지만')
add(n,'A-19','number of iterations마다의 amplitude를','각 number of iterations의 amplitude를')
add(n,'D-14','같은 규칙으로 못 박았습니다.','같은 규칙으로 확정했습니다.')
add(n,'D-14','array를 훔쳐보지 않는다는 16.1절의 원칙이','array에서 정보를 미리 읽지 않는다는 16.1절의 원칙이')
add(n,'D-14','**영원히 bit-exact가 되지 않는데**','**bit-exact가 성립하지 않는데**')
add(n,'D-14','Q1.22 datapath가 무너지기 때문.','Q1.22 datapath를 그대로 쓸 수 없기 때문.')
add(n,'D-14','그것은 amplitude array를 훔쳐보는 반칙입니다.','그것은 amplitude array를 직접 읽는 것처럼 실제 장치에서 얻을 수 없는 정보를 쓰는 일입니다.')
add(n,'A-7','**세 벌(a Checkpoint-Capacity of 3)** 들고 있다가','**세 벌(a Checkpoint-Capacity of 3)** 저장해 두었다가')
add(n,'D-14','Iteration-Count LFSR을 사본으로 굴려','Iteration-Count LFSR의 사본을 전진시켜')
add(n,'D-14','**실기 quantum은 못 하는 반칙**이고,','**실기 quantum에서는 할 수 없는 동작**이고')
add(n,'D-14','checkpoint slot이 살아 있습니다.','checkpoint slot이 유효한 상태로 남습니다.')

n='A_math_review'
add(n,'D-14','이 해설서는 두 가지 배경 지식에 기댑니다.','이 해설서를 읽으려면 두 가지 배경 지식이 필요합니다.')
add(n,'D-14','**linear algebra(vector·matrix)** 위에서 돌아가고,','**linear algebra(vector·matrix)**를 이용하고')
add(n,'D-14','algorithm의 핵심 동력이 되기 때문입니다.','algorithm의 핵심 원리이기 때문입니다.')
add(n,'A-18','이것이 amplitude 한 칸을 fixed-point real number **하나**로 저장하는','이 성질이 amplitude 한 칸을 fixed-point real number **하나**로 저장하는')
add(n,'D-14','라는 수는 이 해설서에서 두 가지 일을 합니다.','라는 수는 이 해설서에서 두 가지 맥락으로 쓰입니다.')
add(n,'D-14','실제로 손을 움직이게 만드는 기호를','실제로 계산에 쓰는 기호를')
add(n,'D-8','그 integer를 어떻게 읽기로 약속했는지가 아래 다섯 가지입니다.','그 integer를 읽고 계산하는 규약 다섯 가지를 아래에 정리했습니다.')
add(n,'D-14','하나로 못 박습니다','일관되게 정의합니다')
add(n,'D-14','circuit 전체가 이 성질 위에 서 있습니다','circuit 전체가 이 성질을 이용합니다')
add(n,'D-14','값은 틀리지만 sign과 크기 순서는 살아남고 error가 그 칸에 머무릅니다','값은 틀리지만 sign과 크기 순서는 유지되고 error는 그 칸에만 남습니다')
add(n,'D-14','그 어긋남의 정체가 바로 이 전제입니다.','이 차이는 위 공식의 전제가 성립하지 않기 때문에 생깁니다.')

manifest=json.loads((ROOT/'group_1.json').read_text())
all_results=[]
for e in manifest['files']:
    rd=Path(e['run_dir']); original=(rd/'01_input.txt').read_text(); edits=EDITS[rd.name]
    actual=[]
    for x in edits:
        count=original.count(x['before'])
        if count==0:
            print('SKIP',rd.name,x['before']);continue
        if count!=1: raise ValueError((rd.name,'nonunique',x['before'],count))
        for pattern in [r"[A-Za-z]+(?:[-_’'][A-Za-z0-9]+)*",r'\d+(?:[.,]\d+)*']:
            if Counter(re.findall(pattern,x['before'])) != Counter(re.findall(pattern,x['after'])):
                raise ValueError((rd.name,'token mismatch',x))
        actual.append(x)
    if e['route']=='heavy':
        cm=json.loads((rd/'chunk_manifest.json').read_text())
        used=[]
        for c in cm['chunks']:
            if c['passthrough']:continue
            combined=(rd/c['input_file']).read_text()
            old=original[c['start']:c['end']]
            assert old.strip() in combined
            out=old
            for x in actual:
                if x['before'] in out:
                    out=out.replace(x['before'],x['after'],1);used.append(x)
            (rd/c['rewritten_file']).write_text(out)
        assert len(used)==len(actual),(rd,len(used),len(actual))
    else:
        combined=(rd/'01_input_with_metrics.txt').read_text();assert original.strip() in combined
        out=original
        for x in actual:out=out.replace(x['before'],x['after'],1)
        summary={'원문_글자수':len(original),'윤문_글자수':len(out),'변경구간':len(actual),'주요_카테고리':sorted({x['rule'] for x in actual}),'등급':'보존 및 gate 검사 후 확정','자체검증':'6항 점검 완료. 교육용 비유·기존 형식 보존. gate 변경률은 주 에이전트가 확정','남은_경고':'없음. 영어·수치·수식·code·제목·link 보존 검사 예정'}
        (rd/'final.md').write_text(out.rstrip()+'\n\n<!-- HUMANIZE-SUMMARY -->\n<!-- '+json.dumps(summary,ensure_ascii=False)+' -->\n')
    (rd/'edits.json').write_text(json.dumps({'edits':actual,'self_check':{'fidelity':True,'conservative':True,'genre':True,'register':True,'targeted_patterns_reviewed':True,'no_new_metaphors_or_claims':True}},ensure_ascii=False,indent=2))
    all_results.append({'file':rd.name,'edits':len(actual)})
print(json.dumps(all_results,ensure_ascii=False,indent=2))
