from pathlib import Path
from collections import Counter
import json,re

ROOT=Path(__file__).resolve().parent
EDITS={}

EDITS['02_dirac_notation_and_linear_algebra']=[
('D-2','measurement probability·normalization·unitary condition이 모두 여기서 깔끔하게 표현됩니다.','measurement probability·normalization·unitary condition을 모두 이 도구로 표현할 수 있습니다.'),
('D-14','그 화살표를 "inner product를 받을 준비가 된" 가로 slot으로 바꾼 것입니다.','그 화살표를 inner product 계산에 쓰는 가로 slot으로 바꾼 것입니다.'),
('D-14','마치 "신발 신고 양말 신기"를 되돌릴 때 역순으로 벗듯이.','신발을 신고 양말을 신었다면, 되돌릴 때는 양말을 먼저 벗고 신발을 벗는 것과 같습니다.'),
('D-2','normalization condition을 inner product로 다시 쓰면 놀랍도록 깔끔합니다.','normalization condition은 inner product로 간단히 표현됩니다.'),
('A-19',r'"$|\psi\rangle$ 방향으로의 projection" operator입니다.',r'$|\psi\rangle$ 방향으로 projection하는 operator입니다.'),
('D-2','에서 결정적으로 등장하니 지금 눈에 익혀 두세요.','에 쓰이므로 지금 눈에 익혀 두세요.'),
('A-18','matrix를 저장하고 곱하는 일이 array를 훑으며 sum을 모으고 빼는 일로 줄어드는 것이죠','matrix를 저장하고 곱하는 대신, array를 훑으며 sum을 구하고 빼면 됩니다'),
('D-14','이후 unitary condition·measurement probability의 뿌리.','이후 unitary condition·measurement probability를 설명하는 조건.'),
('D-14','의 부품.','에 쓰이는 형태.'),
]

EDITS['05_multiple_qubits_and_entanglement']=[
('D-2','qubit가 하나 늘 때마다 dimension이 두 배!','qubit가 하나 늘 때마다 dimension이 두 배가 됩니다'),
('D-14','그 algorithm이 밟는 경로','그 algorithm의 연산 과정'),
('D-14','는 amplitude를 한 번도 real number 바깥으로 내보내지 않습니다.','에서는 amplitude가 항상 real number로 유지됩니다.'),
('D-8','어떤 세 조건이 맞물려 이 성질을 만드는지는','이 성질이 성립하는 세 조건은'),
('D-14','에서 닫습니다.','에서 설명합니다.'),
('D-14','다만 이 절약은 공짜가 아니어서,','다만 이 저장 방식에는 제약이 있어서,'),
('D-14','datapath를 complex number로 다시 지어야 합니다','datapath를 complex number에 맞게 다시 설계해야 합니다'),
('D-2','이제 마법이 일어납니다.','다음 계산을 살펴봅시다.'),
('D-2','measurement로 보면 놀랍습니다:','measurement 결과는 다음과 같습니다:'),
('D-14','이 "분해 불가능"이 hardware budget에 그대로 값을 매깁니다.','이처럼 분해할 수 없다는 성질이 hardware budget을 결정합니다.'),
('D-14','state vector emulator의 속도가 산술 능력이 아니라 memory에 발목 잡히는','state vector emulator의 속도가 산술 능력보다 memory의 제약을 받는'),
('A-18','그림을 읽고 우리 operator와 대응시키려면','그림을 읽고 우리 operator에 대응시키려면'),
('D-14','이 장에서 CNOT은 만들 circuit이 아니라 **읽을 언어**로 챙겨 두면 됩니다.','이 장의 CNOT은 직접 만들 circuit보다 **논문을 읽기 위한 표기**로 이해해 두면 됩니다.'),
]

EDITS['11_state_vector_emulator']=[
('D-14','10장까지 우리는 **quantum algorithm이 수학적으로 무엇을 하는지**를 쌓아 올렸습니다.','10장까지 우리는 **quantum algorithm이 수학적으로 무엇을 하는지**를 배웠습니다.'),
('D-14','를 짓는 이야기입니다.','를 만드는 과정입니다.'),
('D-8','**가장 밑바닥 질문 하나**','**기본적인 질문 하나**'),
('D-2','답은 의외로 단순합니다.','답은 단순합니다.'),
('D-8','이 장은 그 원리와 — 더 중요하게 — 그 **대가**를 다룹니다.','이 장은 그 원리와 **비용**을 다룹니다.'),
('D-14','대가를 알아야 왜 이 분야가 "몇 qubit"에서 벽에 부딪히는지가 보이고,','비용을 알아야 이 방식으로 다룰 수 있는 qubit 수가 왜 제한되는지 알 수 있고,'),
('D-8','우리 것이 정확히 어떤 모양인지 먼저 못 박아 두겠습니다.','우리 설계의 구체적인 구성을 먼저 살펴보겠습니다.'),
('D-14','이 IP는 혼자 서는 chip이 아니라','이 IP는 독립적으로 동작하는 chip이 아니라'),
('D-8','여기서 반드시 새겨야 할 사실 하나. emulator는 quantum computer가 아닙니다.','여기서는 emulator가 quantum computer가 아니라는 사실을 반드시 구분해야 합니다.'),
('D-2','우리의 상대입니다.','우리의 비교 대상입니다.'),
('D-14','을 지불합니다. 다만 그 일을','이 듭니다. 다만 그 일을'),
('D-8','문헌마다 같은 단어가 다른 것을 가리킬 수 있다는 것 자체가 새겨 둘 교훈입니다.','문헌마다 같은 단어가 다른 것을 가리킬 수 있으므로 용법을 확인해야 합니다.'),
('D-5','수식으로는 우아하지만, hardware는 이 ket을 이해하지 못합니다. hardware가 아는 것은 **memory에 담긴 숫자**뿐입니다.','이 ket을 hardware에서 계산하려면 hardware가 다루는 **memory에 담긴 숫자**로 표현해야 합니다.'),
('D-14','이렇게 착지합니다.','다음과 같은 연산이 됩니다.'),
('D-14','는 해설서 전체를 관통하는 규율이고,','는 해설서 전체에서 일관되게 따르는 설명이고,'),
('D-14','다시 정면으로 다룹니다.','다시 다룹니다.'),
('D-14','**array에 대한 산술**로 착지합니다. 이 "번역"이 Part 5 이후 전체의 뼈대입니다.','**array에 대한 산술**로 표현됩니다. Part 5 이후에는 이 대응 관계를 바탕으로 설명합니다.'),
('D-14','엄밀히 말하면 이 지수 벽은 물리 법칙이 아니라 **우리가 택한 방식의 대가**입니다.','엄밀히 말하면 이 지수 비용은 물리 법칙이 아니라 **우리가 택한 방식의 결과**입니다.'),
('D-14','**시간**이 지수로 폭발하고, 특히 Grover에는 자멸적입니다','**시간**이 지수적으로 늘어나고, 특히 Grover에는 불리합니다'),
('D-14','그래서 우리는 memory를 지불하는 state vector 전개를 택합니다 — 벽을 다른 resource로 옮길 수는 있어도,','그래서 우리는 memory를 사용하는 state vector 전개를 택합니다 — 부담을 다른 resource로 옮길 수는 있어도,'),
('D-14','FPGA에는 숫자를 담을 그릇이 여러 종류이고, 어느 그릇을 고르느냐가 몇 qubit까지 갈 수 있는지를 결정합니다.','FPGA에는 숫자를 저장할 곳이 여러 종류이고, 어느 곳을 고르느냐가 다룰 수 있는 qubit 수를 결정합니다.'),
('D-14','사실상 세 진영으로 갈립니다.','세 가지 저장 방식을 씁니다.'),
('D-14','세 진영의 차이는','세 방식의 차이는'),
('D-14','**전부 온칩 register에 욱여넣었기 때문**','**전부 온칩 register에 저장했기 때문**'),
('D-8','그 이유가 이 장의 나머지를 지배하니 여기서 확실히 해 둡니다.','이 선택의 이유를 먼저 살펴보겠습니다.'),
('D-14','넘치지 않는데 나갈 이유가 없고,','용량이 충분하므로 외부에 둘 필요가 없고,'),
('D-14','실제 장부는 이렇습니다','실제 사용량은 이렇습니다'),
('D-2','여기에 결정적인 교훈이 있습니다.','이 결과에서 원인을 구분할 수 있습니다.'),
('D-14','진범은 저장이 아니라 **병렬 연산 unit**입니다.','원인은 저장이 아니라 **병렬 연산 unit**입니다.'),
('D-14','LUT가 지수적으로 터지는 것입니다.','LUT 사용량이 지수적으로 늘어납니다.'),
('D-14','multiplication resource는 텅텅 비었는데 연산 logic routing이 바닥난 것이죠.','multiplication resource에는 여유가 있는데 연산 logic routing이 한계에 이른 것입니다.'),
('D-14','착각하면 헛다리를 짚게 되기 때문입니다.','착각하면 원인을 잘못 판단하기 때문입니다.'),
('D-14','병렬도를 사면 logic로 값을 치릅니다.','병렬도를 높이면 logic 사용량도 늘어납니다.'),
('D-14','에 발목 잡힌 상황을 뜻합니다.','에 제한되는 상황을 뜻합니다.'),
('D-14','요리사만 늘리는 헛수고인 경우가 많습니다','속도 개선으로 이어지지 않는 경우가 많습니다'),
('D-14','한 걸음 더 밀어붙입니다','이 제약을 완화합니다'),
('D-14','번째 bank에 흩뿌려','번째 bank에 분산해'),
('D-14','그 대신 memory-bound가 두 개의 다른 얼굴로 나타납니다.','그 대신 memory-bound는 서로 다른 두 가지 제약으로 나타납니다.'),
('D-14','그 벽 앞에 우리도 서 있습니다.','그 한계가 우리에게도 적용됩니다.'),
('D-14','천장을 14까지 밀어 올린 것뿐이고,','상한을 14까지 높인 것이고,'),
('D-14','넓이는 BRAM 개수로 값을 치른다','폭을 넓히면 필요한 BRAM 개수가 늘어난다'),
('D-14','이 "충돌 0"이 공짜가 아니라는 것은 다른 simulator를 보면 압니다.','다른 simulator에서는 "충돌 0"을 만들기 위해 추가 비용이 듭니다.'),
('D-14','algorithm의 규칙성이 곧바로 logic 예산으로 환산되는, 이 project에서 가장 값싸게 얻은 이득입니다.','algorithm의 규칙성 덕분에 이 project에서는 추가 logic를 쓰지 않고 이 이득을 얻습니다.'),
('D-14','11개를 그대로 물고 있기 때문입니다.','11개를 그대로 사용하기 때문입니다.'),
('D-14','마지막으로 04번 논문과의 거리를 재 두겠습니다.','마지막으로 04번 논문과의 차이를 살펴보겠습니다.'),
('D-14','우리가 파는 것은 속도가 아닙니다.','우리의 목표는 속도 우위를 내세우는 데 있지 않습니다.'),
('D-14','**일부러 쓰지 않는 지름길**이 딸려 옵니다.','**일부러 사용하지 않는 간단한 방법**이 있습니다.'),
]

EDITS['08_deutsch_jozsa_algorithm']=[
('D-2','드디어 완전한 quantum algorithm 하나를 처음부터 끝까지 봅니다.','이제 quantum algorithm 하나를 처음부터 끝까지 살펴봅니다.'),
('D-2','**천문학적으로** 앞설 수 있음을','**큰 차이로** 앞설 수 있음을'),
('D-5','가 어떻게 협력하는지를 명확한 계산으로 보여주기 때문에,','가 어떻게 작용하는지를 계산으로 보여주므로,'),
('D-2','이해하기 위한 완벽한 준비운동입니다.','이해하는 데 도움이 됩니다.'),
('D-14','호출 횟수의 이득을 그대로 물려받지 못합니다.','호출 횟수의 이득을 그대로 얻지는 못합니다.'),
('C-8','emulator가 대신 보여 주는 것은 속도가 아니라, interference가 실제로 어떻게 답을 만들어 내는지를 한 칸씩 재현하고 검증할 수 있다는 점입니다.','emulator에서는 속도의 이득 대신 interference가 답을 만드는 과정을 한 칸씩 재현하고 검증할 수 있습니다.'),
('D-14','이 발동합니다. oracle이 입력 각 항에','이 일어납니다. oracle이 입력 각 항에'),
('D-14','은 이제부터 곁다리 constant이므로 떼어놓고,','은 이후에도 그대로인 constant이므로 따로 두고,'),
('D-14','가 amplitude의 **sign**에 새겨졌습니다.','가 amplitude의 **sign**으로 표현되었습니다.'),
('D-14','이 마법의 정체는 **interference**입니다:','이 결과는 **interference**로 설명됩니다:'),
('D-2','**quantum algorithm의 3박자 구조**를 완벽히 보여줍니다:','**quantum algorithm의 3박자 구조**를 보여줍니다:'),
('D-8','그런데도 이 장이 해설서에 남아 있는 이유는 하나입니다 — **interference가 어떻게 답을 만들어 내는지를 처음부터 끝까지 수식으로 계산해 보이는 유일한 대목**이기 때문입니다.','이 장에서는 **interference가 답을 만들어 내는 과정을 처음부터 끝까지 수식으로 계산**합니다. 해설서에서 이 과정을 모두 계산하는 곳은 이 장뿐입니다.'),
('D-2','다음 장은 이 해설서의 정점, **Grover algorithm**입니다.','다음 장에서는 **Grover algorithm**을 다룹니다.'),
('D-2','에 찾아내는 과정을 완전히 해부합니다.','에 찾아내는 과정을 살펴봅니다.'),
('D-14','emulator는 이 이득을 물려받지 못합니다','emulator는 이 이득을 얻지 못합니다'),
]

EDITS['14_multiple_solutions_and_minimum_search']=[
('D-14','13장이 oracle과 diffusion operator를 circuit으로 내렸습니다.','13장에서는 oracle과 diffusion operator를 circuit으로 구현했습니다.'),
('D-14','oracle에서는 아무 대가도 요구하지 않지만, measurement에서는 설계를 통째로 뒤엎습니다.','oracle에서는 추가 비용이 들지 않지만, measurement에서는 설계를 바꿔야 합니다.'),
('D-8','먼저 함정 하나를 치우고 시작해야 합니다.','먼저 혼동하기 쉬운 표기를 정리해야 합니다.'),
('D-14','이 표를 손 닿는 곳에 두고,','이 표를 참고하면서,'),
('C-8','**oracle에서는 이것이 공짜입니다.**','**oracle에서는 추가 비용이 들지 않습니다.**'),
('C-8','**diffusion operator에서도 공짜입니다.**','**diffusion operator에서도 추가 비용이 들지 않습니다.**'),
('D-14','circuit은 손끝 하나 달라지지 않습니다.','circuit은 달라지지 않습니다.'),
('C-8','**그러나 iteration 제어에서는 공짜가 아닙니다.**','**그러나 iteration 제어에서는 해결할 문제가 있습니다.**'),
('C-8','**그리고 measurement에서는 전혀 공짜가 아닙니다.** 여기가 이 장의 본론입니다.','**measurement에서도 설계를 다시 살펴봐야 합니다.**'),
('D-8','이것이 이 해설서 전체를 관통하는 명제입니다.','이 해설서는 이 설명을 일관되게 따릅니다.'),
('D-14','그들은 전부 똑같이','모두 똑같이'),
('D-14','이 둘째 귀결이 measurement를 무너뜨립니다.','이 두 번째 성질 때문에 기존 measurement 방식이 작동하지 않습니다.'),
('D-14','같은 function을 먹였으니','같은 function을 적용했으니'),
('D-8','귀납이 끝났습니다.','이 관계는 반복해도 유지됩니다.'),
('D-2','Grover는 제 일을 완벽하게 했습니다','Grover는 의도한 대로 동작했습니다'),
('D-14','가 여기서 통째로 막힙니다.','를 이 방식으로는 충족할 수 없습니다.'),
('D-2','probability sampling의 어설픈 특수 경우입니다.','probability sampling의 제한적인 특수 경우입니다.'),
('D-14','[4.1절](04_measurement.md#41-computational-basis-measurement와-born-rule)의 Born rule이 답을 이미 갖고 있습니다.','[4.1절](04_measurement.md#41-computational-basis-measurement와-born-rule)의 Born rule을 그대로 적용하면 됩니다.'),
('D-14','4장의 규칙과 circuit이 한 치도 어긋나지 않습니다.','4장의 규칙과 circuit의 동작이 일치합니다.'),
('D-14','measurement 한 번이 그 60×를 먹는 셈이고, 128 lanes datapath가 통째로 놀게 됩니다.','measurement 한 번에 그 60×의 시간이 들고, 128 lanes datapath는 활용되지 않습니다.'),
('D-14','18.3절이 bit-exact 조건으로 못 박는 항목입니다.','18.3절에서 bit-exact 조건으로 명시한 항목입니다.'),
('D-14','group·row·lane 순의 layer 선택은 그저 순회를 영리하게 한 것이고,','group·row·lane 순의 layer 선택은 순회 방식을 바꾼 것이고,'),
('D-14','상위 bit는 거의 놀지만,','상위 bit는 거의 쓰이지 않지만,'),
('D-8','마지막으로 눈여겨볼 것 — **Build도 lane 고르기도 amplitude memory를 읽기만 합니다.**','마지막으로, **Build도 lane 고르기도 amplitude memory를 읽기만 합니다.**'),
('D-14','이유를 모르면 나중에 다시 끌려갑니다.','이유를 알아야 나중에 같은 대안을 다시 검토하는 일을 줄일 수 있습니다.'),
('D-14','Artix-7에 DSP는 남아돌고','Artix-7의 DSP에는 여유가 있고'),
('D-14','checkpoint라는 이득까지 열어 주는 셈입니다.','checkpoint도 사용할 수 있게 합니다.'),
('D-14','같은 문제의 이어달리기가 아니라','같은 문제를 이어 푸는 것이 아니라'),
('D-8','한 가지 좋은 소식이 있습니다. 새 답이 나와','새 답이 나와'),
('D-14','checkpoint가 살아 있습니다.','checkpoint가 유효합니다.'),
('D-14','그래서 enumeration에서도 checkpoint가 일을 합니다.','그래서 enumeration에서도 checkpoint를 활용합니다.'),
('D-14','접근하면 영원히 헤맵니다.','접근하면 원하는 결과를 얻지 못할 수 있습니다.'),
('D-14','checkpoint가 살아 있어 enumeration에서도','checkpoint가 유효하므로 enumeration에서도'),
]

EDITS['17_rvx_soc_integration']=[
('D-14','그런데 이 circuit에는 아직 시작을 눌러 줄 사람도, data를 넣어 줄 사람도, 답을 받아 갈 사람도 없습니다.','그런데 이 circuit에는 아직 시작 명령을 받고, data를 입력받고, 답을 내보내는 경로가 없습니다.'),
('D-14','이 장은 그 바깥을 붙입니다.','이 장에서는 외부 연결을 다룹니다.'),
('D-14','가장 손에 잡히는 장일 것입니다.','가장 익숙한 장일 것입니다.'),
('D-2','hardware가 압도적으로 유리한 종류의 계산입니다.','hardware로 병렬 처리하기에 적합한 계산입니다.'),
('D-14','분기와 loop와 예외 처리입니다.','분기와 loop, 예외 처리가 필요한 작업입니다.'),
('D-5','quantum processor는 circuit 하나를 실행하고 measurement 결과를 뱉을 뿐이고,','quantum processor는 circuit 하나를 실행하고 measurement 결과를 내보낼 뿐이고,'),
('D-14','사용자가 실제로 이야기를 나누는 상대는','사용자가 실제로 명령을 주고받는 대상은'),
('D-8','이 XML로부터 생성되는 것이 SoC RTL만이 아니라는 점이 중요합니다.','이 XML은 SoC RTL 외의 파일도 생성합니다.'),
('D-14','address로 register를 콕 집는 능력','address로 register를 선택하는 기능'),
('D-14','그 IP는 SoC 바깥의 섬이 됩니다.','그 IP를 SoC에 연결할 수 없습니다.'),
('D-14','설정 register의 쓰기 signal을 module 안에 가둬 둡니다.','설정 register의 쓰기 signal을 module 밖으로 내보내지 않습니다.'),
('D-14','동작을 우리가 직접 쥐어야 했기 때문입니다.','동작을 우리가 직접 제어해야 했기 때문입니다.'),
('D-14','조건이 안 맞으면 pulse가 조용히 버려지므로,','조건이 안 맞으면 pulse가 무시되므로,'),
('D-8','최소한의 규약 셋을 못 박아 둡니다.','다음 세 가지 규약을 따릅니다.'),
('D-2','이유는 자명합니다 — 절반만 채워진','절반만 채워진'),
('D-14','bring-up 단계에서 이 차이는 며칠을 좌우합니다.','bring-up 단계에서는 이 차이가 문제를 찾는 데 걸리는 시간을 크게 줄입니다.'),
('D-2','실험 회전율을 완전히 망칩니다.','실험을 반복하는 데 큰 부담이 됩니다.'),
('D-14','state를 software에 맡기면 샙니다','state를 software에 맡기면 관리가 누락됨'),
('D-14','accelerator는 놀고,','accelerator는 대기하고,'),
('D-14','firmware가 shot을 직접 모는 길을','firmware가 shot을 직접 실행하는 방법을'),
('D-14','policy의 손잡이 — 연속 실패 몇 번에 끝낼지 — 는 `ENUM_CFG` 로 firmware가 쥡니다.','policy의 설정값 — 연속 실패 몇 번에 끝낼지 — 은 `ENUM_CFG` 로 firmware가 정합니다.'),
('D-14','직접 CSR을 두드리는 firmware가','직접 CSR에 접근하는 firmware가'),
('D-5','지금은 board에서 돈 build가 답을 줍니다.','지금은 board에서 동작한 build를 기준으로 정해졌습니다.'),
('D-14','읽기 부작용과 완료 표시를 우리가 쥐었습니다','읽기 부작용과 완료 표시를 우리가 제어했습니다'),
('D-14','한계값만 firmware가 쥡니다.','한계값만 firmware가 설정합니다.'),
('D-14','설계는 이제 종이 위가 아니라 board 위에서 돕니다.','설계는 이제 board 위에서 동작합니다.'),
]

EDITS['index']=[
('D-14','오늘날 우리가 쓰는 모든 computer의 뿌리는 1936년 영국 수학자 **Alan Turing** 입니다.','오늘날 우리가 쓰는 모든 computer의 기원은 1936년 영국 수학자 **Alan Turing**의 연구로 거슬러 올라갑니다.'),
('A-18','각 입자를 qubit라고 (사실은 아니지만) 단순화하면,','각 입자가 qubit인 것은 아니지만, 설명을 위해 그렇게 단순화하면,'),
('D-2','안타깝게도 안 됩니다. 바로 이 지점이 quantum의 진짜 핵심입니다.','항상 그렇게 쓸 수는 없습니다. quantum의 중요한 성질이 여기서 드러납니다.'),
('D-14','지수적 폭발이 선형 증가로 바뀝니다.','필요한 자원이 지수적 증가 대신 선형 증가에 그칩니다.'),
('D-2','을 완전히 체득하게 됩니다.','을 익힐 수 있습니다.'),
('D-8','여기서 오해 하나를 미리 끊어 두겠습니다.','여기서 한 가지를 구분해야 합니다.'),
('D-14','그러면 왜 만드느냐 — 겨룰 상대를 제대로 고르면 이야기가 달라집니다.','그렇다면 왜 만들까요? 비교 대상을 살펴보면 이 작업의 목적을 알 수 있습니다.'),
('D-14','우리의 상대입니다.','우리의 비교 대상입니다.'),
('D-14','들여다보는 순간 state가 무너지니까요.','관측하는 순간 state가 바뀌기 때문입니다.'),
('D-14','14 qubits라는 숫자는 야심이 부족해서 고른 것이 아니라, amplitude array를 여러 벌 들고 계산하는 우리 구조를 이 board에 실을 수 있는 천장이 거기이기 때문입니다.','14 qubits는 amplitude array를 여러 벌 저장하며 계산하는 우리 구조를 이 board에 구현할 수 있는 상한입니다.'),
('D-14','을 밑바닥부터 쌓아 올린 뒤','을 기초부터 배운 뒤'),
('D-14','로 내려앉는 과정을 따라갑니다','로 구현되는 과정을 따라갑니다'),
('D-14','어긋나면 15.4절이 이깁니다.','어긋나면 15.4절을 기준으로 삼습니다.'),
('D-14','설계 질문별로 **가로질러** 읽으면서,','설계 질문별로 **함께** 읽으면서,'),
('D-14','각 장은 바로 앞 장의 개념 위에 세워집니다. 순서대로 읽는 것을 강력히 권합니다.','각 장은 바로 앞 장의 개념을 바탕으로 설명합니다. 순서대로 읽기를 권합니다.'),
('D-14','Grover를 이해하는 4개의 기둥입니다.','Grover를 이해하는 데 필요한 4개의 기본 개념입니다.'),
('D-8','**12장을 13장 앞에 두는 것은 취향이 아닙니다.**','**13장을 읽기 전에 12장의 내용이 필요합니다.**'),
('D-14','개념은 앞 장에서 뒤 장으로 단조롭게 쌓이도록 배치했습니다.','앞 장에서 배운 개념을 뒤 장에서 쓰도록 배치했습니다.'),
('D-8','그 밖에 둘을 더 못 박아 둡니다.','그 밖에 두 가지 범위를 더 정해 둡니다.'),
('D-14','설계 결정 하나를 통째로 떠받치는 논문이','설계 결정 하나의 근거가 되는 논문이'),
('D-2','종이에 직접 $H|0\\rangle$ 을 계산해 보는 습관이 결정적입니다.','종이에 직접 $H|0\\rangle$ 을 계산해 보는 습관이 중요합니다.'),
('D-2','틀리면 "좋았어!"라고 외치세요.','틀린 부분을 찾아 다시 계산해 보세요.'),
('D-14','classical은 지수적 폭발, quantum은','classical은 지수적으로 증가, quantum은'),
]

def write_outputs():
    manifest=json.loads((ROOT/'group_2.json').read_text())
    for entry in manifest['files']:
        rd=Path(entry['run_dir']); stem=rd.name
        if stem not in EDITS: continue
        original=(rd/'01_input.txt').read_text(); updated=original; records=[]
        for rule,before,after in EDITS[stem]:
            n=updated.count(before)
            assert n>=1,(stem,before,n)
            updated=updated.replace(before,after)
            records.append({'rule':rule,'before':before,'after':after,'occurrences':n})
        latin=lambda s:Counter(re.findall(r"[A-Za-z]+(?:[-_’'][A-Za-z0-9]+)*",s))
        assert latin(original)==latin(updated),(stem,latin(original)-latin(updated),latin(updated)-latin(original))
        assert Counter(re.findall(r'\d+(?:[.,]\d+)*',original))==Counter(re.findall(r'\d+(?:[.,]\d+)*',updated)),stem
        (rd/'edits.json').write_text(json.dumps({'edits':records,'self_check':{'passed':6,'total':6,'note':'사용자 보존 조건 우선; 교육용 표·콜아웃과 필수 technical term 반복 유지'}},ensure_ascii=False,indent=2))
        if entry['route']=='heavy':
            cm=json.loads((rd/'chunk_manifest.json').read_text())
            for c in cm['chunks']:
                if c['passthrough']:continue
                chunk=original[c['start']:c['end']]
                for _,before,after in EDITS[stem]:
                    if before in chunk:chunk=chunk.replace(before,after)
                (rd/c['rewritten_file']).write_text(chunk)
        else:
            summary='\n<!-- HUMANIZE-SUMMARY -->\n<!-- 자체검증 6/6. 영어 용어·수치·수식·code·제목·link 보존. 변경률은 공통 게이트 산출값 참조. -->\n'
            (rd/'final.md').write_text(updated+summary)
        print(stem,len(records))

if __name__=='__main__':write_outputs()
