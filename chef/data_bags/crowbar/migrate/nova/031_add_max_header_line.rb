def upgrade ta, td, a, d
  a['max_header_line'] = 16384
  return a, d
end

def downgrade ta, td, a, d
  a.delete('max_header_line')
  return a, d
end
