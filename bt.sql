create database mini;
use mini;

drop database mini;


-- 1. TABLE USERS

CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);


-- 2. TABLE POSTS

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    content TEXT NOT NULL,

    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_posts_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

-- FULLTEXT SEARCH

ALTER TABLE posts
ADD FULLTEXT(content);

-- 3. TABLE COMMENTS

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_comments_posts
    FOREIGN KEY (post_id)
    REFERENCES posts(post_id),

    CONSTRAINT fk_comments_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);


-- 4. TABLE LIKES

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,

    user_id INT NOT NULL,
    post_id INT NOT NULL,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_user_post
    UNIQUE(user_id, post_id),

    CONSTRAINT fk_likes_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id),

    CONSTRAINT fk_likes_posts
    FOREIGN KEY (post_id)
    REFERENCES posts(post_id)
);


-- 5. TABLE FRIENDS

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,

    user_id INT NOT NULL,
    friend_id INT NOT NULL,

    status VARCHAR(20)
    CHECK(status IN ('pending', 'accepted')),

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_not_self_friend
    CHECK(user_id <> friend_id),

    CONSTRAINT fk_friends_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id),

    CONSTRAINT fk_friends_friend
    FOREIGN KEY (friend_id)
    REFERENCES users(user_id)
);


-- 6. TABLE POST LOGS

CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    post_content TEXT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 1
create view view_user_info as
select user_id, username, email,created_at 
from users;

select * from view_user_info;


-- 2 
delimiter //
create procedure  sp_add_user (
in p_username varchar(50),
in p_password varchar(50),
in p_email  varchar(50)
)

begin
declare check_username int ;
declare check_email int;

select count(*) into check_username from users where username = p_username;
if check_username > 0 then select 'username đã tồn tại';
else 
select count(*) into check_email from users where email = p_email;
if check_email > 0 
then 
     signal sqlstate '45000'
     set message_text = 'email đã tồn tại';
	else 
    insert into users(username,password,email)
    values (p_username,p_password,p_email );
    end if;
end if;

end//

delimiter ;


call sp_add_user('thienduc','123','thienduc@gmail.com');







--  3
drop trigger tg_after_like_insert;
delimiter $$

-- tăng like khi chèn vào bảng likes
create trigger tg_after_like_insert
after insert on likes
for each row
begin
    update posts 
    set like_count = like_count + 1 
    where post_id = new.post_id;
end $$

-- giảm like khi xóa khỏi bảng likes (có chặn < 0)
create trigger tg_after_like_delete
after delete on likes
for each row
begin
    update posts 
    set like_count = case 
        when like_count > 0 then like_count - 1 
        else 0 
    end
    where post_id = old.post_id;
end $$

-- tăng comment khi chèn vào bảng comments
create trigger tg_after_comment_insert
after insert on comments
for each row
begin
    update posts 
    set comment_count = comment_count + 1 
    where post_id = new.post_id;
end $$

-- giảm comment khi xóa khỏi bảng comments (có chặn < 0)
create trigger tg_after_comment_delete
after delete on comments
for each row
begin
    update posts 
    set comment_count = case 
        when comment_count > 0 then comment_count - 1 
        else 0 
    end
    where post_id = old.post_id;
end $$

delimiter ;


-- 4
 delimiter $$ 
 create procedure sp_user_activity_report ()
 begin 
	select 
        u.user_id,
        u.username,
        count(distinct p.post_id) as total_posts,
        count(distinct l.like_id) as total_likes,
        count(distinct c.comment_id) as total_comments
    from users u
    left join posts p on u.user_id = p.user_id
    left join likes l on u.user_id = l.user_id
    left join comments c on u.user_id = c.user_id
    group by u.user_id, u.username;
 end $$
 delimiter ;


-- 5 
delimiter $$
create procedure sp_delete_user  (
	in p_user_id int 
) 
begin 
	--  tạo biến để lưu trữ 
declare v_user_count int;

    -- check xem user có tồn tại không trước khi làm việc
    select count(*) into v_user_count from users where user_id = p_user_id;

    if v_user_count = 0 then
        signal sqlstate '45000'
        set message_text = 'lỗi: người dùng không tồn tại';
    else
        -- bắt đầu giao dịch an toàn
        start transaction;

        -- 1. xóa likes (những lượt like mà user này đã đi bấm)
        delete from likes where user_id = p_user_id;

        -- 2. xóa comments (những bình luận mà user này đã viết)
        delete from comments where user_id = p_user_id;

        -- 3. xóa friends (xóa các mối quan hệ bạn bè liên quan)
        delete from friends where user_id = p_user_id or friend_id = p_user_id;

        -- 4. xử lý các bài viết của user (posts)
        -- lưu ý: phải xóa sạch like/comment nằm trong các bài viết này trước
        delete from likes where post_id in (select post_id from posts where user_id = p_user_id);
        delete from comments where post_id in (select post_id from posts where user_id = p_user_id);
        
        -- sau đó mới xóa bài viết
        delete from posts where user_id = p_user_id;

        -- 5. xóa bảng cha cuối cùng
        delete from users where user_id = p_user_id;

        -- kiểm tra nếu xóa user thành công thì chốt dữ liệu, ngược lại thì hồi lại hết
        if row_count() > 0 then
            commit;
        else
            rollback;
            signal sqlstate '45000'
            set message_text = 'lỗi: quá trình xóa thất bại, đã rollback';
        end if;
    end if;



end $$
delimiter ;


delimiter //
create trigger tg_before_friend_insert
before insert on friends
for each row
begin
  if new.user_id = new.friend_id then
    signal sqlstate '45000' set message_text = 'không thể tự kết bạn với chính mình';
  elseif exists (select 1 from friends where user_id = new.user_id and friend_id = new.friend_id) then
    signal sqlstate '45000' set message_text = 'cặp bạn bè đã tồn tại';
  elseif exists (select 1 from friends where user_id = new.friend_id and friend_id = new.user_id) then
    signal sqlstate '45000' set message_text = 'đã có lời mời đảo chiều';
  end if;
end;

end // 
delimiter ;

