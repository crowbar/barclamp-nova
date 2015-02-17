def upgrade ta, td, a, d
  a['vnc_keymap'] = ta['vnc_keymap']
  return a, d
end

def downgrade ta, td, a, d
  a.delete 'vnc_keymap'
  return a, d
end
