# InstaLink-Mood-Based-Social-Stranger-Connection-App
A Kotlin + Java Full-Stack Mobile App
InstaLink is a social discovery app similar to Instagram but with a unique twist—users can connect with strangers based on their mood.
A user posts how they feel → AI detects mood → App finds another user with a similar emotional post → both get a private 10-minute timed chat → if they both “Like the Chat”, they can add each other as friends.

⭐ Key Features
📸 Instagram-like Social Feed

Create posts (text, image)

Like, comment, and profile view

Real-time updates using Firestore

💬 StrangerConnect – Mood-Based Matching

User posts how they feel

AI extracts mood keywords using NLP

System finds another user with related mood words

Connects two strangers for a 10-minute private chat

⏳ Timed Chat System

Chat expires automatically after 10 minutes

Both users can:

👍 Like the chat → becomes a permanent friendship

👎 End the chat forever

🎭 Mood AI Engine

Uses simple Java NLP keyword extraction

Tags moods: happy, sad, stressed, excited, lonely, etc.

🔐 Authentication

Firebase Authentication (email/password)

☁️ Backend

Spring Boot (Java)

WebSockets for real-time chats

Firestore for chat & profile storage

🏗 System Architecture
Android App (Kotlin + MVVM)
   ↓
Firebase Auth
   ↓
Spring Boot Server (Java)
   - Mood Matching Engine
   - WebSocket Chat Server
   ↓
Firestore Database

📁 Folder Structure
InstaLink/
 ├── android-app/
 │    ├── app/src/main/java/com/instalink/
 │    │        ├── ui/
 │    │        ├── viewmodel/
 │    │        ├── adapters/
 │    │        ├── models/
 │    │        └── network/
 │    └── resources/
 ├── backend/
 │    ├── src/main/java/com/instalink/api/
 │    │        ├── controllers/
 │    │        ├── services/
 │    │        ├── websocket/
 │    │        └── nlp/
 │    └── resources/
 ├── README.md
 └── LICENSE

🧠 AI Mood Matching (Java Backend Code)
MoodService.java
@Service
public class MoodService {

    private static final Map<String, List<String>> moodKeywords = Map.of(
            "happy", List.of("joy", "excited", "great", "awesome"),
            "sad", List.of("depressed", "low", "unhappy", "tears"),
            "angry", List.of("mad", "furious", "irritated"),
            "lonely", List.of("alone", "isolated", "ignored")
    );

    public String detectMood(String postText) {
        String lower = postText.toLowerCase();

        return moodKeywords.entrySet().stream()
                .filter(entry -> entry.getValue()
                        .stream().anyMatch(lower::contains))
                .map(Map.Entry::getKey)
                .findFirst()
                .orElse("neutral");
    }
}

🔥 Mood-Based Stranger Matching API
MatchController.java
@RestController
@RequestMapping("/match")
public class MatchController {

    @Autowired
    private MoodService moodService;

    @Autowired
    private UserService userService;

    @GetMapping("/{userId}")
    public ResponseEntity<?> matchUser(@PathVariable String userId) {

        User user = userService.getUser(userId);
        String mood = moodService.detectMood(user.getLatestPost());

        User match = userService.findUserWithMood(mood, userId);

        return ResponseEntity.ok(Map.of(
                "matchedUserId", match.getId(),
                "mood", mood
        ));
    }
}

🔌 WebSocket Real-Time Chat (Java Spring Boot)
ChatSocket.java
@Component
public class ChatSocket {

    private Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();

    @OnOpen
    public void onOpen(WebSocketSession session) {
        sessions.put(session.getId(), session);
    }

    @OnMessage
    public void onMessage(String message, WebSocketSession session) throws IOException {
        for (WebSocketSession s : sessions.values()) {
            if (!s.getId().equals(session.getId())) {
                s.sendMessage(new TextMessage(message));
            }
        }
    }

    @OnClose
    public void onClose(WebSocketSession session) {
        sessions.remove(session.getId());
    }
}

📱 Android (Kotlin) Timed Chat Screen
ChatViewModel.kt
class ChatViewModel : ViewModel() {

    private val _timeLeft = MutableLiveData<Int>()
    val timeLeft: LiveData<Int> = _timeLeft

    private var timer: CountDownTimer? = null

    fun startChatTimer() {
        timer = object : CountDownTimer(10 * 60 * 1000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                _timeLeft.value = (millisUntilFinished / 1000).toInt()
            }

            override fun onFinish() {
                endChatSession()
            }
        }.start()
    }

    fun endChatSession() {
        // Close chat, update backend
    }
}

📡 Android WebSocket Connection (Kotlin)
ChatSocket.kt
class ChatSocket(url: String) {

    private val client = OkHttpClient()
    private val request = Request.Builder().url(url).build()
    private var webSocket: WebSocket? = null

    fun connect(onMessage: (String) -> Unit) {
        webSocket = client.newWebSocket(request, object : WebSocketListener() {

            override fun onMessage(ws: WebSocket, text: String) {
                onMessage(text)
            }
        })
    }

    fun sendMessage(msg: String) {
        webSocket?.send(msg)
    }
}

📸 Posting Feeling (Kotlin)
fun uploadFeelingPost(text: String, userId: String) {
    val post = hashMapOf(
        "userId" to userId,
        "text" to text,
        "timestamp" to System.currentTimeMillis()
    )
    FirebaseFirestore.getInstance()
        .collection("moodPosts")
        .add(post)
}

🚀 How to Run
Backend
cd backend
./mvnw spring-boot:run

Android App

Open in Android Studio → Run on emulator or device.
