import os
import sys

# Add repository root to Python path so `import app` works in CI
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
