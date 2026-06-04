from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from app.database import get_db
from app.models.database import User
from app.models.schemas import UserCreate, UserResponse, LoginRequest, Token
from app.auth.jwt_handler import get_password_hash, verify_password, create_access_token

router = APIRouter()

@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate, db: AsyncSession = Depends(get_db)):
    """Registers a new user, hashes the password, and returns user details."""
    result = await db.execute(select(User).where(User.email == user_data.email))
    existing_user = result.scalars().first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email is already registered"
        )
    
    hashed_password = get_password_hash(user_data.password)
    new_user = User(
        email=user_data.email,
        display_name=user_data.display_name,
        hashed_password=hashed_password,
        avatar_url=user_data.avatar_url,
    )
    
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    return new_user

@router.post("/login", response_model=Token)
async def login(login_data: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticates credentials and returns a bearer token."""
    result = await db.execute(select(User).where(User.email == login_data.email))
    user = result.scalars().first()
    if not user or not user.hashed_password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password"
        )
    
    if not verify_password(login_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password"
        )
        
    access_token = create_access_token(data={"user_id": user.id, "email": user.email})
    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/apple", response_model=Token)
async def apple_login(apple_payload: dict, db: AsyncSession = Depends(get_db)):
    """Handles Apple Sign In with real credential tokens.
    
    In production, the identity_token JWT should be verified against Apple's
    public keys at https://appleid.apple.com/auth/keys. For local development,
    we accept the token and create/lookup the user by apple_id.
    """
    email = apple_payload.get("email")
    display_name = apple_payload.get("display_name", "Apple User")
    apple_id = apple_payload.get("apple_id")
    identity_token = apple_payload.get("identity_token")
    authorization_code = apple_payload.get("authorization_code")
    
    if not apple_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing apple_id in payload"
        )
    
    # Log received credentials (never log tokens in production)
    import logging
    logger = logging.getLogger(__name__)
    logger.info(f"Apple Sign In: apple_id={apple_id[:12]}..., email={email}, "
                f"has_identity_token={identity_token is not None}, "
                f"has_auth_code={authorization_code is not None}")
    
    # TODO: In production, verify identity_token JWT signature against Apple's public keys
    # https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/verifying_a_user
    
    # Lookup or create user by apple_id
    result = await db.execute(select(User).where(User.apple_id == apple_id))
    user = result.scalars().first()
    
    if not user:
        # Check if email already exists (link accounts)
        if email:
            result = await db.execute(select(User).where(User.email == email))
            user = result.scalars().first()
        
        if not user:
            # Create new user from Apple credentials
            # Generate a placeholder email if Apple didn't provide one (private relay)
            final_email = email or f"{apple_id[:16]}@privaterelay.appleid.com"
            user = User(
                email=final_email,
                display_name=display_name,
                apple_id=apple_id,
            )
            db.add(user)
            await db.commit()
            await db.refresh(user)
        else:
            # Link existing email-based account to Apple ID
            user.apple_id = apple_id
            if display_name and display_name != "Apple User":
                user.display_name = display_name
            await db.commit()
            await db.refresh(user)
    
    access_token = create_access_token(data={"user_id": user.id, "email": user.email})
    return {"access_token": access_token, "token_type": "bearer"}

