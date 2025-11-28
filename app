Data Base
# Lightweight SQLite persistence for users and messages.
import databases, sqlalchemy, datetime, os

DATABASE_URL = 'sqlite:///instalink.db'
database = databases.Database(DATABASE_URL)
metadata = sqlalchemy.MetaData()

users = sqlalchemy.Table(
    'users', metadata,
    sqlalchemy.Column('id', sqlalchemy.Integer, primary_key=True),
    sqlalchemy.Column('username', sqlalchemy.String, unique=False),
    sqlalchemy.Column('mood', sqlalchemy.String),
    sqlalchemy.Column('created_at', sqlalchemy.DateTime, default=datetime.datetime.utcnow)
)

messages = sqlalchemy.Table(
    'messages', metadata,
    sqlalchemy.Column('id', sqlalchemy.Integer, primary_key=True),
    sqlalchemy.Column('from_user', sqlalchemy.String),
    sqlalchemy.Column('to_user', sqlalchemy.String),
    sqlalchemy.Column('text', sqlalchemy.String),
    sqlalchemy.Column('timestamp', sqlalchemy.DateTime, default=datetime.datetime.utcnow)
)

def get_engine():
    url = DATABASE_URL.replace('sqlite:///', 'sqlite:///')  # ensure proper path
    engine = sqlalchemy.create_engine(url, connect_args={"check_same_thread": False})
    return engine

async def init_db():
    engine = get_engine()
    metadata.create_all(engine)
    await database.connect()

async def save_user(username, mood):
    query = users.insert().values(username=username, mood=mood, created_at=datetime.datetime.utcnow())
    last_id = await database.execute(query)
    return last_id

async def update_user_mood(user_id, mood):
    query = users.update().where(users.c.id == user_id).values(mood=mood)
    await database.execute(query)

async def save_message(from_user, to_user, text):
    query = messages.insert().values(from_user=from_user, to_user=to_user, text=text, timestamp=datetime.datetime.utcnow())
    await database.execute(query)

async def get_recent_messages(limit=100):
    query = messages.select().order_by(messages.c.id.desc()).limit(limit)
    rows = await database.fetch_all(query)
    return [dict(r) for r in reversed(rows)]




main....
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
import asyncio, json, time
from .models import UserCreate, User, Message
from . import db

app = FastAPI(title='InstaLink - Mood-Based Connection App')
app.mount('/static', StaticFiles(directory='static'), name='static')

# simple in-memory connection store and matching queue
class ConnectionManager:
    def __init__(self):
        self.active: dict[str, WebSocket] = {}  # username -> websocket
        self.waiting: list[dict] = []  # list of {username, mood}

    async def connect(self, username: str, websocket: WebSocket):
        await websocket.accept()
        self.active[username] = websocket

    def disconnect(self, username: str):
        if username in self.active:
            del self.active[username]
        # remove from waiting queue if present
        self.waiting = [w for w in self.waiting if w.get('username') != username]

    async def send_personal(self, username: str, message: dict):
        ws = self.active.get(username)
        if ws:
            await ws.send_text(json.dumps(message))

    async def broadcast(self, message: dict):
        for ws in list(self.active.values()):
            try:
                await ws.send_text(json.dumps(message))
            except:
                pass

    def add_waiting(self, username: str, mood: str):
        # avoid duplicates
        self.waiting = [w for w in self.waiting if w.get('username') != username]
        self.waiting.append({'username': username, 'mood': mood, 'timestamp': time.time()})

    def find_match(self, username: str, mood: str):
        # matching rules: prefer same mood, otherwise complementary (simple mapping)
        complementary = {
            'sad': ['comforting','neutral','happy'],
            'lonely': ['friendly','talkative','happy'],
            'happy': ['happy','celebratory','lonely'],
            'curious': ['curious','helpful','knowledgeable']
        }
        # try same mood first
        for w in self.waiting:
            if w['username'] != username and w['mood'] == mood:
                return w['username']
        # then complementary
        comps = complementary.get(mood, [])
        for w in self.waiting:
            if w['username'] != username and w['mood'] in comps:
                return w['username']
        return None

manager = ConnectionManager()

@app.on_event('startup')
async def startup():
    await db.init_db()

@app.post('/api/register')
async def register_user(payload: UserCreate):
    # naive registration: store username + mood
    # In real app, add auth and validation
    uid = await db.save_user(payload.username, payload.mood)
    return {'id': uid, 'username': payload.username, 'mood': payload.mood}

@app.post('/api/update_mood/{username}')
async def update_mood(username: str, payload: dict):
    mood = payload.get('mood')
    if not mood:
        raise HTTPException(status_code=400, detail='mood required')
    # store in waiting queue for matching
    manager.add_waiting(username, mood)
    return {'status': 'queued', 'username': username, 'mood': mood}

@app.get('/api/history')
async def history(limit: int = 100):
    rows = await db.get_recent_messages(limit=limit)
    return rows

@app.websocket('/ws/{username}')
async def websocket_endpoint(websocket: WebSocket, username: str):
    await manager.connect(username, websocket)
    try:
        while True:
            data = await websocket.receive_text()
            payload = json.loads(data)
            # handle commands: {type: 'find'}, {type: 'message', to:'other', text:'...'}, {type:'leave'}
            t = payload.get('type')
            if t == 'find':
                mood = payload.get('mood')
                manager.add_waiting(username, mood)
                match = manager.find_match(username, mood)
                if match:
                    # remove both from waiting
                    manager.waiting = [w for w in manager.waiting if w['username'] not in (username, match)]
                    # notify both users with a 'matched' event
                    await manager.send_personal(username, {'type':'matched', 'peer': match})
                    await manager.send_personal(match, {'type':'matched', 'peer': username})
                else:
                    await manager.send_personal(username, {'type':'searching'})
            elif t == 'message':
                to = payload.get('to')
                text = payload.get('text')
                # relay message
                await db.save_message(username, to, text)
                await manager.send_personal(to, {'type':'message', 'from': username, 'text': text})
            elif t == 'leave':
                peer = payload.get('peer')
                # notify peer
                await manager.send_personal(peer, {'type':'system', 'text': f'{username} left the chat'})
            else:
                await manager.send_personal(username, {'type':'error', 'text':'unknown command'})
    except WebSocketDisconnect:
        manager.disconnect(username)




models.....
from pydantic import BaseModel
from typing import Optional

class UserCreate(BaseModel):
    username: str
    mood: str  # e.g., 'happy', 'sad', 'lonely', 'curious'

class User(BaseModel):
    id: int
    username: str
    mood: str
    ws_id: Optional[str] = None

class Message(BaseModel):
    from_user: str
    to_user: str
    text: str
    timestamp: Optional[str] = None
