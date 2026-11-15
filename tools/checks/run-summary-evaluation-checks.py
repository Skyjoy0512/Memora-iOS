"""Free CI: pin/license/data audit and metric gates. No API credentials or dependencies."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('jmeet', root / 'tools/evaluation/jmeeteval_offline.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
_, _, records, categories = module.load_data()
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(root / 'tools/evaluation/tests'),
                '-p', 'test_metrics.py', '-v'], check=True)
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(root / 'tools/evaluation/tests'), '-p', 'test_gold.py', '-v'], check=True)
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(root / 'tools/evaluation/tests'), '-p', 'test_report.py', '-v'], check=True)
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(root / 'tools/evaluation/tests'), '-p', 'test_model_runner.py', '-v'], check=True)
print(json.dumps({'pinnedJMeetEvalRecords': len(records), 'categories': len(categories), 'apiRequests': 0}))
