
rm -r keys/
mkdir keys

ssh-keygen -q -C example@example.com -t ed25519 -m rfc4716 -f keys/ssh_ed25519_none.key -N ''
ssh-keygen -q -C example@example.com -t ed25519 -m rfc4716 -f keys/ssh_ed25519_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ed25519 -m rfc4716 -f keys/ssh_ed25519_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ed25519 -m rfc4716 -f keys/ssh_ed25519_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ed25519 -m rfc4716 -f keys/ssh_ed25519_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ed25519 -m pkcs8 -f keys/pkcs8_ed25519_none.key -N ''
ssh-keygen -q -C example@example.com -t ed25519 -m pkcs8 -f keys/pkcs8_ed25519_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ed25519 -m pkcs8 -f keys/pkcs8_ed25519_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ed25519 -m pkcs8 -f keys/pkcs8_ed25519_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ed25519 -m pkcs8 -f keys/pkcs8_ed25519_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t rsa -b 2048 -m rfc4716 -f keys/ssh_rsa2048_none.key -N ''
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m rfc4716 -f keys/ssh_rsa2048_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m rfc4716 -f keys/ssh_rsa2048_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m rfc4716 -f keys/ssh_rsa2048_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m rfc4716 -f keys/ssh_rsa2048_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t rsa -b 2048 -m pkcs8 -f keys/pkcs8_rsa2048_none.key -N ''
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m pkcs8 -f keys/pkcs8_rsa2048_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m pkcs8 -f keys/pkcs8_rsa2048_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m pkcs8 -f keys/pkcs8_rsa2048_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t rsa -b 2048 -m pkcs8 -f keys/pkcs8_rsa2048_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m rfc4716 -f keys/ssh_ecdsa256_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m rfc4716 -f keys/ssh_ecdsa256_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m rfc4716 -f keys/ssh_ecdsa256_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m rfc4716 -f keys/ssh_ecdsa256_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m rfc4716 -f keys/ssh_ecdsa256_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m pkcs8 -f keys/pkcs8_ecdsa256_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m pkcs8 -f keys/pkcs8_ecdsa256_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m pkcs8 -f keys/pkcs8_ecdsa256_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m pkcs8 -f keys/pkcs8_ecdsa256_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 256 -m pkcs8 -f keys/pkcs8_ecdsa256_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m rfc4716 -f keys/ssh_ecdsa384_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m rfc4716 -f keys/ssh_ecdsa384_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m rfc4716 -f keys/ssh_ecdsa384_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m rfc4716 -f keys/ssh_ecdsa384_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m rfc4716 -f keys/ssh_ecdsa384_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m pkcs8 -f keys/pkcs8_ecdsa384_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m pkcs8 -f keys/pkcs8_ecdsa384_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m pkcs8 -f keys/pkcs8_ecdsa384_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m pkcs8 -f keys/pkcs8_ecdsa384_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 384 -m pkcs8 -f keys/pkcs8_ecdsa384_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m rfc4716 -f keys/ssh_ecdsa521_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m rfc4716 -f keys/ssh_ecdsa521_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m rfc4716 -f keys/ssh_ecdsa521_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m rfc4716 -f keys/ssh_ecdsa521_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m rfc4716 -f keys/ssh_ecdsa521_aes192cbc.key -N 'password' -Z aes192-cbc

ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m pkcs8 -f keys/pkcs8_ecdsa521_none.key -N ''
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m pkcs8 -f keys/pkcs8_ecdsa521_aes256ctr.key -N 'password' -Z aes256-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m pkcs8 -f keys/pkcs8_ecdsa521_aes192ctr.key -N 'password' -Z aes192-ctr
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m pkcs8 -f keys/pkcs8_ecdsa521_aes256cbc.key -N 'password' -Z aes256-cbc
ssh-keygen -q -C example@example.com -t ecdsa -b 521 -m pkcs8 -f keys/pkcs8_ecdsa521_aes192cbc.key -N 'password' -Z aes192-cbc

for key in keys/*.key; do
    ssh-keygen -Y sign -P 'password' -f $key -n 'something' $key.pub
done
