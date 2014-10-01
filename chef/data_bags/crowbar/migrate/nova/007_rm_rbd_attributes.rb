def upgrade ta, td, a, d
  a.delete('rbd')
  return a, d
end

def downgrade ta, td, a, d
  a['rbd'] = {}
  a['rbd']['user'] = ''
  a['rbd']['secret_uuid'] = ''
end
