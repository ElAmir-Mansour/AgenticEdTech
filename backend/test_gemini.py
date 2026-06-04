import os
import asyncio
from dotenv import load_dotenv
from langchain_google_genai import ChatGoogleGenerativeAI

load_dotenv()
api_key = os.getenv("GOOGLE_API_KEY")

async def test_model(model_name):
    print(f"Testing {model_name}...")
    try:
        llm = ChatGoogleGenerativeAI(model=model_name, google_api_key=api_key)
        res = await llm.ainvoke("Say hello")
        print(f"SUCCESS {model_name}: {res.content}")
    except Exception as e:
        print(f"FAILED {model_name}: {e}")

async def main():
    models_to_test = [
        "gemini-2.0-flash",
        "gemini-2.0-flash-exp",
        "gemini-1.5-flash",
        "gemini-1.5-flash-latest",
        "gemini-1.5-pro",
        "gemini-pro"
    ]
    for m in models_to_test:
        await test_model(m)

if __name__ == "__main__":
    asyncio.run(main())
