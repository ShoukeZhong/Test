/// 感測器寫進來、大腦讀出去的「當下刺激」。所有感測都在手機上算，影像和聲音不存檔、不上傳。
enum BodyRegion { head, cheek, back, belly, tail, legs }

class Stimuli {
  // 聽覺（麥克風）
  bool micOn = false;
  double soundLevel = 0; // 0..1，相對環境底噪
  bool loudOnset = false; // 突然的大聲（拍手、東西掉落）
  double voiceSeconds = 0; // 持續像說話／叫名字的聲音

  // 視覺（前鏡頭）
  bool cameraOn = false;
  double brightness = 0.5; // 0..1，瞳孔大小跟著變
  double motion = 0; // 0..1 鏡頭前的動作量
  double motionX = 0.5; // 0..1 動作在畫面左右的位置
  bool motionBurst = false; // 突然的大動作

  // 觸覺（螢幕）
  BodyRegion? strokeRegion; // 正在撫摸的部位
  double strokeSpeed = 0; // 世界單位／秒
  double sinceStroke = 99; // 距上次撫摸幾秒
  bool poke = false; // 戳一下
  double? fingerX; // 手指在貓旁邊滑動（像逗貓棒）；世界座標
  double fingerY = 0;
  double fingerSpeed = 0;
  bool touchingPet = false;

  void clearOneShots() {
    loudOnset = false;
    motionBurst = false;
    poke = false;
  }
}
