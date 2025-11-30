import os
from datetime import datetime, timedelta
from typing import List, Optional
from enum import Enum

from fastapi.middleware.cors import CORSMiddleware 

from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File, Form

from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import sessionmaker, Session, declarative_base, relationship
from passlib.context import CryptContext
from jose import JWTError, jwt


DATABASE_URL = "mysql+pymysql://root:@localhost/paquexpress_db" 
SECRET_KEY = "tu_clave_secreta_super_segura"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60
UPLOAD_DIR = "uploads"


os.makedirs(UPLOAD_DIR, exist_ok=True)


engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()





app = FastAPI(title="API Paquexpress", description="Backend para app de entregas")
origins = [
    "http://localhost",
    "http://127.0.0.1",
    "http://127.0.0.1:8000",

    "*" 
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins, 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"], 
)




class UserDB(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True)
    hashed_password = Column(String(255))
    full_name = Column(String(100))
    is_active = Column(Boolean, default=True)
    packages = relationship("PackageDB", back_populates="agent")

class PackageDB(Base):
    __tablename__ = "packages"
    id = Column(Integer, primary_key=True, index=True)
    tracking_number = Column(String(50), unique=True)
    destination_address = Column(String(255))
    dest_lat = Column(Float)
    dest_lng = Column(Float)
    status = Column(String(20), default="pendiente") 
    assigned_agent_id = Column(Integer, ForeignKey("users.id"))
    

    proof_photo_url = Column(String(255), nullable=True)
    delivery_lat = Column(Float, nullable=True)
    delivery_lng = Column(Float, nullable=True)
    delivered_at = Column(DateTime, nullable=True)
    
    agent = relationship("UserDB", back_populates="packages")

Base.metadata.create_all(bind=engine)


class Token(BaseModel):
    access_token: str
    token_type: str

class UserCreate(BaseModel):
    username: str
    password: str
    full_name: str

class PackageResponse(BaseModel):
    id: int
    tracking_number: str
    destination_address: str
    dest_lat: float
    dest_lng: float
    status: str
    
    class Config:
        orm_mode = True

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudieron validar las credenciales",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = db.query(UserDB).filter(UserDB.username == username).first()
    if user is None:
        raise credentials_exception
    return user





app.mount("/static", StaticFiles(directory=UPLOAD_DIR), name="static")


@app.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(UserDB).filter(UserDB.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token = create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/users/")
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    hashed_password = get_password_hash(user.password)
    db_user = UserDB(username=user.username, hashed_password=hashed_password, full_name=user.full_name)
    db.add(db_user)
    db.commit()
    return {"msg": "Usuario creado exitosamente"}


@app.post("/packages/create")
def create_package(tracking: str, address: str, lat: float, lng: float, agent_username: str, db: Session = Depends(get_db)):
    agent = db.query(UserDB).filter(UserDB.username == agent_username).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agente no encontrado")
        
    pkg = PackageDB(
        tracking_number=tracking,
        destination_address=address,
        dest_lat=lat,
        dest_lng=lng,
        assigned_agent_id=agent.id
    )
    db.add(pkg)
    db.commit()
    return {"msg": "Paquete asignado correctamente"}


@app.get("/deliveries/assigned", response_model=List[PackageResponse])
def get_assigned_packages(current_user: UserDB = Depends(get_current_user), db: Session = Depends(get_db)):
    packages = db.query(PackageDB).filter(
        PackageDB.assigned_agent_id == current_user.id,
        PackageDB.status == "pendiente"
    ).all()
    return packages


@app.post("/deliveries/{package_id}/confirm")
async def confirm_delivery(
    package_id: int,
    file: UploadFile = File(...),
    lat: float = Form(...),
    lng: float = Form(...),
    current_user: UserDB = Depends(get_current_user),
    db: Session = Depends(get_db)
):
 
    package = db.query(PackageDB).filter(
        PackageDB.id == package_id,
        PackageDB.assigned_agent_id == current_user.id
    ).first()
    
    if not package:
        raise HTTPException(status_code=404, detail="Paquete no encontrado o no asignado a este agente")
    
    if package.status == "entregado":
        raise HTTPException(status_code=400, detail="El paquete ya fue entregado")


    file_extension = file.filename.split(".")[-1]
    filename = f"delivery_{package.tracking_number}_{int(datetime.utcnow().timestamp())}.{file_extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)
    
    with open(file_path, "wb") as buffer:
        buffer.write(await file.read())
        

    package.proof_photo_url = f"/static/{filename}"
    package.delivery_lat = lat
    package.delivery_lng = lng
    package.status = "entregado"
    package.delivered_at = datetime.utcnow()
    
    db.commit()
    
    return {"msg": "Entrega registrada exitosamente", "timestamp": package.delivered_at}