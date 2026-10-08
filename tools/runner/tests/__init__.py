from runner.common import long_temp

# Before any test: an 8.3 short TEMP (C:\Users\XPERIA~1\...) in its long form, as tools/run.py does (issue #542), so
# `python -m unittest runner.tests.<module>` compares the paths git and Path.resolve give with tempfile's.
long_temp()
