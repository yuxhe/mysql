-- Procedure structure for `sp_json`
-- ----------------------------
DROP PROCEDURE IF EXISTS `sp_json`;
DELIMITER ;;
CREATE DEFINER=`wsq`@`%` PROCEDURE `sp_json`(json TEXT,out  jsonOut  varchar(1000), out  errorMsg varchar(200))
    DETERMINISTIC
BEGIN



/* 功能 调用服务

      创建者   yuxh

      创建时间 2014-4-16

      传入参数 json的字符串,

      返回  返回输出的jsonout,错误提示信息

 */ 

-- json(json text,search_key varchar(255)) return  value 

-- 函数功能  传入json格式串及键值，返回键对应的值 

-- 函数调用方式 select  json('{name:\'zzzz\',nameb:"aaaaa",namec:456}','name')

-- 动态产生变量及其对应的值

-- -- 核心算法以冒号为基准分离 

   declare stmt_prim varchar(5000);

   set @errorMsg="";

   set @servicename=json(json,'servicename');
   set @methodp=json(json,'method'); -- method
   set @IP4=REPLACE(json(json,'IP4'),'$','.'); -- IP地址
   set @app=json(json,'app'); -- app标识,sbid####app
   /*
   select  servicep into @servicep  from  sys_service_name  where  servicename=@servicename ;

   select  found_rows() into @count ;
   */
   -- 直接采用传入服务名字
   set @servicep:=@servicename;
   set @count:=1;

   if  @count<=0 THEN
       set errorMsg="{\"id\":\"900\",\"Msg\":\"无此服务!\"}";
   ELSE       
       -- 记录操作日志
       insert into sys_service_rz (SERVICENAME,METHOD,NOTE,RQ,IP,APP) VALUES (@servicep,@methodp,concat("'",replace(json,"\"","\\\""),"',@aa,@bb"),now(),@IP4,@app);
       set @stmt_json:=CONCAT("call ", @servicep ,"('",json,"',@jsonOut,@errorMsg)");
       -- select  json;
       prepare stmt_prim from @stmt_json;
       execute stmt_prim ;
       set errorMsg= @errorMsg;
       set jsonOut= @jsonOut;
       -- add yuxh on 2014-8-28 增加监控返回jsonOut为空的情况，导致前端报错
       if  jsonOut is null THEN
           insert into businesslog(businessnote,operatedate) values(concat(@servicep," -> ",@methodp,',jsonOut结果为null'),now());
       end if;
       -- add yuxh on 2014-6-27 清空连接的@类型变量数据，设置为null;目的防止基于连接的变量相互干扰
       call sp_json_parm_tonull(json,@a5);
       deallocate prepare stmt_prim;

   end if;

END
;;
DELIMITER ;

-- ----------------------------
-- Procedure structure for `sp_json_parm`
-- ----------------------------
DROP PROCEDURE IF EXISTS `sp_json_parm`;
DELIMITER ;;
CREATE DEFINER=`wsq`@`%` PROCEDURE `sp_json_parm`(json TEXT,out  parm varchar(1000))
    DETERMINISTIC
BEGIN

/* 功能 解析出所有的json 键值对

      创建者   yuxh

      创建时间 2014-4-16
      传入参数 json的字符串,parm 键
      返回  解析出所有的json 键值对
 */ 

-- json(json text,search_key varchar(255)) return  value 

-- 函数功能  传入json格式串及键值，返回键对应的值 

-- 函数调用方式 select  json('{name:\'zzzz\',nameb:"aaaaa",namec:456}','name')

-- 动态产生变量及其对应的值

-- -- 核心算法以冒号为基准分离 

DECLARE i INT DEFAULT 1; 
DECLARE json_length INT DEFAULT LENGTH(json); 
DECLARE state ENUM('reading_key','done_reading_key','reading_string', 'reading_number'); 
DECLARE tmp_key TEXT;
DECLARE tmp_value TEXT; 

declare stmt  varchar(5000);

DECLARE current_char VARCHAR(1);

set state="reading_key";

set tmp_key='';
set tmp_value='';
WHILE i <= json_length DO 
SET current_char = SUBSTRING(json,i,1); 
IF state = 'reading_key' THEN
   -- 核心算法以冒号为基准分离 
   IF current_char = ':' THEN 

      SET state = 'done_reading_key';

   elseif current_char != '{' and  current_char != ',' and  current_char != '"' and  current_char != "'" THEN 

      SET tmp_key = CONCAT(tmp_key, current_char);   

   END IF; 



ELSEIF state = 'done_reading_key' THEN

   IF current_char = '"' or  current_char = "'" THEN 

      SET state = 'reading_string'; 

   ELSEIF IsNumeric(current_char)=1 and IS$(json,i)=0 THEN 

      SET state = 'reading_number'; 

      SET tmp_value=CONCAT(tmp_value, SUBSTRING(json,i,1)); 

   -- 特殊处理空值情况 null

   elseif current_char=',' and  upper(trim(tmp_value))='NULL'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   elseif current_char=',' and  upper(trim(tmp_value))='TRUE'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=1');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   elseif current_char=',' and  upper(trim(tmp_value))='FALSE'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=0');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   ELSE

      SET tmp_value = CONCAT(tmp_value, current_char);

   END IF; 

ELSEIF state = 'reading_string' THEN 

   IF current_char = '\\' THEN 

      SET i = i + 1; 

      SET tmp_value = CONCAT(tmp_value, SUBSTRING(json,i,1));

    ELSEIF (state = 'reading_string' AND (current_char = '"' or current_char = "'"))  THEN  

      -- 处理具体的值

      if  tmp_value="" then

          set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      else

          set @sql_json_parm:=concat('select "',tmp_value, '" into @',trim(tmp_key));

      end if;
      
      prepare stmt from  @sql_json_parm;

      execute stmt;       
      

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   ELSE 

      SET tmp_value = CONCAT(tmp_value, current_char); 

   END IF; 

ELSEIF (state = 'reading_number') THEN

  -- 特殊处理取数字 

  IF (state = 'reading_number' AND ( (current_char!='.'  and isNumeric(current_char)!=1)) or (current_char='.' and  INSTR(tmp_value,'.')>0) ) THEN   

           

        -- 处理具体的值

        set @sql_json_parm:=concat('select ',tmp_value, ' into @',trim(tmp_key));

        prepare stmt from @sql_json_parm;

        execute stmt;         

        -- 特殊处理i值

        if  LOCATE(",",json,i) >0 THEN

            set i=LOCATE(",",json,i);

        end if;      

        SET state = "reading_key"; 

        set tmp_key='';

        set tmp_value='';

  ELSE     

       SET tmp_value=CONCAT(tmp_value, SUBSTRING(json,i,1)); 

  END IF; 

  ELSE 

  IF current_char='"' or  current_char="'" THEN 

     SET state = 'reading_key'; 

     SET tmp_key = ''; 

     SET tmp_value = ''; 

  END IF; 

END IF; 

   SET i = i + 1; 

END WHILE;  

   set parm="";

END
;;
DELIMITER ;

-- ----------------------------
-- Procedure structure for `sp_json_parm_tonull`
-- ----------------------------
DROP PROCEDURE IF EXISTS `sp_json_parm_tonull`;
DELIMITER ;;
CREATE DEFINER=`wsq`@`%` PROCEDURE `sp_json_parm_tonull`(json TEXT,out  parm varchar(1000))
    DETERMINISTIC
BEGIN

/* 功能 解析出所有的json 键值对

      创建者   yuxh

      创建时间 2014-6-27
      传入参数 json的字符串,parm 键
      返回  解析出所有的json 键值对 ；add yuxh on 2014-6-27 清空连接的@类型变量数据，设置为null;目的防止基于连接的变量相互干扰
 */ 

-- json(json text,search_key varchar(255)) return  value 

-- 函数功能  传入json格式串及键值，返回键对应的值 

-- 函数调用方式 select  json('{name:\'zzzz\',nameb:"aaaaa",namec:456}','name')

-- 动态产生变量及其对应的值

-- -- 核心算法以冒号为基准分离 

DECLARE i INT DEFAULT 1; 
DECLARE json_length INT DEFAULT LENGTH(json); 
DECLARE state ENUM('reading_key','done_reading_key','reading_string', 'reading_number'); 
DECLARE tmp_key TEXT;
DECLARE tmp_value TEXT; 

declare stmt  varchar(5000);

DECLARE current_char VARCHAR(1);

set state="reading_key";

set tmp_key='';
set tmp_value='';
WHILE i <= json_length DO 
SET current_char = SUBSTRING(json,i,1); 
IF state = 'reading_key' THEN
   -- 核心算法以冒号为基准分离 
   IF current_char = ':' THEN 

      SET state = 'done_reading_key';

   elseif current_char != '{' and  current_char != ',' and  current_char != '"' and  current_char != "'" THEN 

      SET tmp_key = CONCAT(tmp_key, current_char);   

   END IF; 



ELSEIF state = 'done_reading_key' THEN

   IF current_char = '"' or  current_char = "'" THEN 

      SET state = 'reading_string'; 

   ELSEIF IsNumeric(current_char)=1 and IS$(json,i)=0 THEN 

      SET state = 'reading_number'; 

      SET tmp_value=CONCAT(tmp_value, SUBSTRING(json,i,1)); 

   -- 特殊处理空值情况 null

   elseif current_char=',' and  upper(trim(tmp_value))='NULL'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   elseif current_char=',' and  upper(trim(tmp_value))='TRUE'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   elseif current_char=',' and  upper(trim(tmp_value))='FALSE'  THEN

      -- set @sql_json_parm:=concat('select "',null, '" into @',trim(tmp_key));

      set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   ELSE

      SET tmp_value = CONCAT(tmp_value, current_char);

   END IF; 

ELSEIF state = 'reading_string' THEN 

   IF current_char = '\\' THEN 

      SET i = i + 1; 

      SET tmp_value = CONCAT(tmp_value, SUBSTRING(json,i,1));

    ELSEIF (state = 'reading_string' AND (current_char = '"' or current_char = "'"))  THEN  

      -- 处理具体的值

      if  tmp_value="" then

          set @sql_json_parm:=concat('set ', '@',trim(tmp_key),':=null');

      else

          set @sql_json_parm:=concat('select null into @',trim(tmp_key));

      end if;



      prepare stmt from  @sql_json_parm;

      execute stmt;       

      SET state = "reading_key"; 

      set tmp_key='';

      set tmp_value='';

   ELSE 

      SET tmp_value = CONCAT(tmp_value, current_char); 

   END IF; 

ELSEIF (state = 'reading_number') THEN

  -- 特殊处理取数字 

  IF (state = 'reading_number' AND ( (current_char!='.'  and isNumeric(current_char)!=1)) or (current_char='.' and  INSTR(tmp_value,'.')>0) ) THEN   

           

        -- 处理具体的值

        set @sql_json_parm:=concat('select null into @',trim(tmp_key));

        prepare stmt from @sql_json_parm;

        execute stmt;         

        -- 特殊处理i值

        if  LOCATE(",",json,i) >0 THEN

            set i=LOCATE(",",json,i);

        end if;      

        SET state = "reading_key"; 

        set tmp_key='';

        set tmp_value='';

  ELSE     

       SET tmp_value=CONCAT(tmp_value, SUBSTRING(json,i,1)); 

  END IF; 

  ELSE 

  IF current_char='"' or  current_char="'" THEN 

     SET state = 'reading_key'; 

     SET tmp_key = ''; 

     SET tmp_value = ''; 

  END IF; 

END IF; 

   SET i = i + 1; 

END WHILE;  

   set parm="";

END
;;
DELIMITER ;
