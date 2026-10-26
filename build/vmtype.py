import sys, subprocess
# Text per QEMU sendkey tippen (US-Layout wie in GRUB)
m={' ':'spc','$':'shift-4','/':'slash','.':'dot','-':'minus','_':'shift-minus','(':'shift-9',')':'shift-0',',':'comma','=':'equal',':':'shift-semicolon','"':'shift-apostrophe','\n':'ret'}
vm=sys.argv[1]; txt=sys.argv[2]
for c in txt:
    k=m.get(c) or (('shift-'+c.lower()) if c.isupper() else c)
    subprocess.run([vm,'cmd','sendkey '+k],capture_output=True)
