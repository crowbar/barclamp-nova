# -*- encoding : utf-8 -*-
def upgrade ta, td, a, d
  a['rbd'] = {}
  a['rbd']['user'] = ''
  a['rbd']['secret_uuid'] = ''
  return a, d
end

def downgrade ta, td, a, d
  a.delete('rbd')
  return a, d
end
