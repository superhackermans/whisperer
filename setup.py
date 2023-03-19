from setuptools import setup
import sys

sys.setrecursionlimit(3000)

APP = ['whisperergui.py']
DATA_FILES = ['assets/mic_on.png', 'assets/mic_off.png']
OPTIONS = {
    'argv_emulation': True,
    'includes': [
        'config',
        'core',
        'phrases',
        'rumps',
        'pynput',
        'numpy',
        'pyaudio',
        'pyperclip',
        'rubicon.objc',
    ],
    'plist': {
        'LSUIElement': True,
    },
    'packages': [
        'rumps',
        'pynput',
        'numpy',
        'pyaudio',
        'pyperclip',
        'yaml',
        'rubicon',
    ],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
