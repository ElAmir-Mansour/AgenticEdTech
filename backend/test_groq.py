import os
import asyncio
from dotenv import load_dotenv
from langchain_groq import ChatGroq

load_dotenv()
api_key = os.getenv("GROQ_API_KEY")

async def test_model(model_name):
    print(f"Testing {model_name}...")
    try:
        llm = ChatGroq(model=model_name, groq_api_key=api_key)
        res = await llm.ainvoke("Say hello")
        print(f"SUCCESS {model_name}: {res.content}")
    except Exception as e:
        print(f"FAILED {model_name}: {e}")

async def main():
    models_to_test = [
        "llama-3.3-70b-versatile",
        "llama-3.1-70b-versatile",
        "llama3-8b-8192",
        "llama3-70b-8192"
    ]
    for m in models_to_test:
        await test_model(m)

if __name__ == "__main__":
    asyncio.run(main())
