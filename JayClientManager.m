//
//  JayClientManager.m
//  MQTTTest
//
//  Created by barara on 16/3/24.
//  Copyright © 2016年 Jay. All rights reserved.
//

#import "JayClientManager.h"
#import <AudioToolbox/AudioToolbox.h>
#import "FriendModel.h"
#import <ShareSDK/ShareSDK.h>
#import <AssetsLibrary/AssetsLibrary.h>

static JayClientManager *instance = nil;

@interface JayClientManager ()
@property (nonatomic,strong)NSString *sender;
@property (nonatomic,strong)NSString *senderNickName;
@property (nonatomic,strong)NSString *sendTime;
@property (nonatomic,strong)NSArray *msgArray;
@property (nonatomic,strong)NSMutableString *messageStr;
@property (nonatomic,strong)UILocalNotification *localNotification;
@property (nonatomic,strong)NSString *localBody;
@property (nonatomic,strong)NSString *msgType;
@end
@implementation JayClientManager

+ (instancetype)sharedClient
{
    //单例
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        instance = [[self alloc] init];
        
    });
    return instance;
}

- (void)createManager
{
    //把deviceId作为mqtt的clientId   port为端口号  username是用户名 password是密码
    NSString *deviceId = [[[UIDevice currentDevice]identifierForVendor]UUIDString];
    NSString *clientId = [NSString stringWithFormat:@"%@", deviceId];
    
    /*
     * MQTTClient: create an instance of MQTTSessionManager once and connect
     * will is set to let the broker indicate to other subscribers if the connection is lost
     */
    
    if (!self.manager) {
        self.manager = [[MQTTSessionManager alloc] init];
        self.manager.delegate = self;
        //self.manager.subscriptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:MQTTQosLevelExactlyOnce] forKey:[NSString stringWithFormat:@"%@/#", self.base]];
        [self.manager connectTo:AliYunMQTT_HOST
                           port:1883
                            tls:NO
                      keepalive:5
                          clean:NO
                           auth:false
                           user:nil
                           pass:nil
                      willTopic:nil
                           will:nil
                        willQos:0
                 willRetainFlag:FALSE
                   withClientId:clientId];
    } else {
        [self.manager connectToLast];
    }
    
    /*
     * MQTTCLient: observe the MQTTSessionManager's state to display the connection status
     */
    
    [self.manager addObserver:self
                   forKeyPath:@"state"
                      options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                      context:nil];
}

- (instancetype)init
{
    if (self = [super init]) {
        
        [self createManager];
        
        //判断是否已登录，打开不同的数据库
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"userData"]) {
            NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
            NSDictionary *userInfoDict = dict[@"userInfo"];
            NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
            
            //实例化fmdb
            _db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/%@chatLog.db", NSHomeDirectory(),userIdStr]];
            //打开数据库
            BOOL res = [_db open];
            if (res == NO) {
                NSLog(@"数据库打开失败");
            } else {
                NSLog(@"数据库打开成功");
            }
            
        } else {
            
            //实例化fmdb
            _db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/chatLog.db", NSHomeDirectory()]];
            //打开数据库
            BOOL res = [_db open];
            if (res == NO) {
                NSLog(@"数据库打开失败");
            } else {
                NSLog(@"数据库打开成功");
            }
            
        }
        
        _isExistMessage = NO;
        
        //创建串行队列
        _queue = dispatch_queue_create("sqlThread", NULL);
        _dataQueue = dispatch_queue_create("dataThread", NULL);
        _publishDynamicQueue = dispatch_queue_create("publishDynamicThread", NULL);
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    switch (self.manager.state) {
        case MQTTSessionManagerStateClosed:
            
            break;
        case MQTTSessionManagerStateClosing:
            
            break;
        case MQTTSessionManagerStateConnected:
            
            [self.manager connectToLast];
            break;
        case MQTTSessionManagerStateConnecting:
            
            break;
        case MQTTSessionManagerStateError:
            [self.manager connectToLast];
            break;
        case MQTTSessionManagerStateStarting:
            break;
        default:
            break;
    }
}

//登录成功调用，更改数据库
- (void)loginSuccessToChangeDb
{
    BOOL res = [_db close];
    if (res == NO) {
        NSLog(@"数据库关闭失败");
    }
    
    _db = nil;
    
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
    NSDictionary *userInfoDict = dict[@"userInfo"];
    NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
    //实例化fmdb
    _db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/%@chatLog.db", NSHomeDirectory(),userIdStr]];
    //打开数据库
    BOOL resLogin = [_db open];
    if (resLogin == NO) {
        NSLog(@"数据库打开失败");
    }
}
//退出登录调用，更改数据库
- (void)exitLoginToChangeDb
{
    BOOL res = [_db close];
    if (res == NO) {
        NSLog(@"数据库关闭失败");
    }
    
    _db = nil;
    
    //实例化fmdb
    _db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/chatLog.db", NSHomeDirectory()]];
    //打开数据库
    BOOL resChatLog = [_db open];
    if (resChatLog == NO) {
        NSLog(@"数据库打开失败");
    }
}

//获取屏幕当前展示的页面
- (UIViewController *)getCurrentVC
{
    UIViewController *result = nil;
    
    UIWindow * window = [[UIApplication sharedApplication] keyWindow];
    if (window.windowLevel != UIWindowLevelNormal)
    {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for(UIWindow * tmpWin in windows)
        {
            if (tmpWin.windowLevel == UIWindowLevelNormal)
            {
                window = tmpWin;
                break;
            }
        }
    }
    
    UIView *frontView = [[window subviews] objectAtIndex:0];
    id nextResponder = [frontView nextResponder];
    
    if ([nextResponder isKindOfClass:[UIViewController class]])
        result = nextResponder;
    else
        result = window.rootViewController;
    
    return result;
}
//获取模态出来的页面
- (UIViewController *)getPresentedViewController
{
    UIViewController *appRootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController *topVC = appRootVC;
    if (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    return topVC;
}
//退出登陆，以未登陆状态刷新所有页面
- (void)exitLogin
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"userData"]) {
        
        NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
        NSDictionary *userInfoDict = dict[@"userInfo"];
        NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
        //取消关注自己的主题
        [[JayClientManager sharedClient].manager.session unsubscribeTopic:[NSString stringWithFormat:RECEIVE_ALL_MSG_TOPIC_FORMAT,[NSString stringWithFormat:@"user-%@",userIdStr]] unsubscribeHandler:^(NSError *error) {
            
            if (error) {
                NSLog(@"取消关注自己的主题失败");
            } else {
                NSLog(@"取消关注自己的主题成功");
            }
            
        }];
        //判断是否授权
        if ([ShareSDK hasAuthorized:SSDKPlatformTypeSinaWeibo]) {
            [ShareSDK cancelAuthorize:SSDKPlatformTypeSinaWeibo];
        }
        if ([ShareSDK hasAuthorized:SSDKPlatformTypeWechat]) {
            [ShareSDK cancelAuthorize:SSDKPlatformTypeWechat];
        }
        if ([ShareSDK hasAuthorized:SSDKPlatformTypeQQ]) {
            [ShareSDK cancelAuthorize:SSDKPlatformTypeQQ];
        }
        /*
         *
         *  在这里取消关注NSUserDefaults存储的群
         *
         */
        NSString * shopIdString = [NSString stringWithFormat:@"shop-%@",[[NSUserDefaults standardUserDefaults] objectForKey:@"groupId"]];
        if (shopIdString) {
            //取消关注
            [[JayClientManager sharedClient].manager.session unsubscribeTopic:[NSString stringWithFormat:RECEIVE_ALL_MSG_TOPIC_FORMAT,shopIdString] unsubscribeHandler:^(NSError *error) {
                
                if (error) {
                    NSLog(@"取消关注群主题失败");
                } else {
                    NSLog(@"取消关注群主题成功");
                }
                
            }];
            
        }
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"userData"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"groupId"];
        
        //更换数据库
        dispatch_async([JayClientManager sharedClient].queue, ^{
            [[JayClientManager sharedClient] exitLoginToChangeDb];
            dispatch_async(dispatch_get_main_queue(), ^(){//这里是主线程，在此处更新界面
                if (!_mybar) {
                    return;
                }
                
                for (UINavigationController *getNC in self.mybar.childViewControllers) {
                    if (getNC.viewControllers.count > 1) {
                        [getNC popToRootViewControllerAnimated:YES];
                        [ZHLNotificationCenter postNotificationName:ZHLPopViewControllerNotification object:nil];
                    }
                }
                
                UINavigationController *nc = [self.mybar.childViewControllers objectAtIndex:3];
                PersonViewController *personVC = [nc.viewControllers objectAtIndex:0];
                personVC.isLogin = NO;
                [personVC.tableView reloadData];
                
                UIAlertView *alertview = [[UIAlertView alloc] initWithTitle:@"提示" message:@"您的账号已在其他设备登陆，请重新登陆" delegate:self cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [alertview show];
                
            });
        });
    }
    
    
}

//接收消息回调
/*
 * MQTTSessionManagerDelegate
 */
- (void)handleMessage:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained {
    /*
     * MQTTClient: process received message
     */
    
    
    NSMutableDictionary *receiveDic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    NSLog(@"收到的消息为:%@,topic为%@",receiveDic,topic);
    
    [self mgrReceiveMessageWith:receiveDic];
}

//接收消息
- (void)mgrReceiveMessageWith:(NSMutableDictionary *)dict
{
    __weak JayClientManager *blockSelf = self;
    
    //        NSString *text = message.payloadString;
    //        NSString *topic = message.topic;
    //        NSLog(@"received message is %@,\ntopic = %@", text,topic);
    
    dispatch_async(blockSelf.queue, ^{
        
        //判断数据库是否存在
        if (!blockSelf.db) {
            //判断是否已登录，打开不同的数据库
            if ([[NSUserDefaults standardUserDefaults] objectForKey:@"userData"]) {
                NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
                NSDictionary *userInfoDict = dict[@"userInfo"];
                NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
                //实例化fmdb
                blockSelf.db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/%@chatLog.db", NSHomeDirectory(),userIdStr]];
                //打开数据库
                BOOL res = [blockSelf.db open];
                if (res == NO) {
                    NSLog(@"数据库打开失败");
                } else {
                    NSLog(@"数据库打开成功");
                }
            } else {
                //实例化fmdb
                blockSelf.db = [[FMDatabase alloc] initWithPath:[NSString stringWithFormat:@"%@/Documents/chatLog.db", NSHomeDirectory()]];
                //打开数据库
                BOOL res = [blockSelf.db open];
                if (res == NO) {
                    NSLog(@"数据库打开失败");
                } else {
                    NSLog(@"数据库打开成功");
                }
            }
        }
        
        //NSArray *msgArr = dict[Mqtt_msg];
        //NSLog(@"received dic = %@",dict);
        
        //消息中有参数为空
        if (!(dict[Mqtt_sender] && dict[Mqtt_receiver] && dict[Mqtt_msgType] && dict[Mqtt_chatType] && dict[Mqtt_msg] && dict[Mqtt_sendTime])) {
            return;
        }
        
        //登陆消息
        if ([[NSString stringWithFormat:@"%@",dict[Mqtt_chatType]] isEqualToString:MqttChatTypeEnum_STATE] && [[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_ONLINE_STATE_CHAT]) {
            
            NSArray *msgArr = dict[Mqtt_msg];
            if (![[NSString stringWithFormat:@"%@",msgArr[2]] isEqualToString:[[[UIDevice currentDevice]identifierForVendor]UUIDString]]) {
                [blockSelf exitLogin];
            }
            
            return;
        }
        
        //            if ([[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_FRIEND]) {
        //                NSLog(@"收到好友相关消息，dic = %@",dict);
        //            }
        
        if ([[NSString stringWithFormat:@"%@",dict[Mqtt_chatType]] isEqualToString:[NSString stringWithFormat:MqttChatTypeEnum_CHAT]]) {
            //收到的是单聊的消息
            
            NSArray *msgArray = dict[Mqtt_msg];
            if ([[NSString stringWithFormat:@"%@",msgArray.firstObject] isEqualToString:MqttFriendRelationTypeEnum_DELETE] && [[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_FRIEND]) {
                
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                if (blockSelf.messageBlock) {
                    blockSelf.messageBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                }
                
                return;
            }
            
            //在线程中的数据库操作
            //dispatch_async([JayClientManager sharedClient].queue, ^{
            
            if ([[NSUserDefaults standardUserDefaults] objectForKey:@"blackList"]) {//有黑名单
                NSArray *list = [[NSUserDefaults standardUserDefaults] objectForKey:@"blackList"];
                BOOL isBlackList = [list containsObject:dict[Mqtt_sender]];
                if (isBlackList == YES) {//在黑名单里面
                    return;
                }
            }
            
            
            //动态消息
            if ([[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_COMMENT_DYNAMIC]) {
                //如果动态表不存在，就创建一张动态表
                NSString *createDynamicTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead)",Table_Dynamic_Format];
                BOOL resDynamicTableMsg = [blockSelf.db executeUpdate:createDynamicTableStr];
                if (resDynamicTableMsg == NO) {
                    NSLog(@"创建动态表失败");
                }
                
                //msg字符串
                NSData *msgData = [NSJSONSerialization dataWithJSONObject:dict[Mqtt_msg] options:0 error:nil];
                NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
                
                NSString *insertDynamicStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead) values('%@','%@','%@','%@','%@','%@','%@')",Table_Dynamic_Format,dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],[NSString stringWithFormat:@"1"]];
                BOOL resDynamic = [blockSelf.db executeUpdate:insertDynamicStr];
                if (resDynamic == NO) {
                    NSLog(@"添加一条动态数据失败");
                }
                
                //如果消息表不存在，就创建一张消息表
                NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
                BOOL resTableMsg = [blockSelf.db executeUpdate:createMessageTableStr];
                if (resTableMsg == NO) {
                    NSLog(@"创建消息表失败");
                }
                
                //查询消息表中动态数据的条数，正常为0（无动态）或1（有动态）
                NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@ where msgType='%@'",Table_Message_Format,MqttMsgTypeEnum_COMMENT_DYNAMIC];
                int count = [blockSelf.db intForQuery:getCountStr];
                if (count == 0) {
                    
                    NSString *addMessageStr = [NSString stringWithFormat:@"insert into Table_Message(sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite) values('%@','%@','%@','%@','%@','%@',%@,'%@')",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@1,dict[Mqtt_receiver]];
                    BOOL resAddMsg = [blockSelf.db executeUpdate:addMessageStr];
                    if (resAddMsg == NO) {
                        NSLog(@"添加一条消息表动态失败");
                    }
                    
                } else {
                    
                    NSString *lastNumStr = [NSString stringWithFormat:@"SELECT msgNumber FROM %@ WHERE msgType= '%@' LIMIT 1",Table_Message_Format,MqttMsgTypeEnum_COMMENT_DYNAMIC];
                    int lastNum = [blockSelf.db intForQuery:lastNumStr];
                    
                    NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set sender='%@',receiver='%@',msgType='%@',chatType='%@',msg='%@',sendTime='%@',msgNumber=%d where msgType='%@'",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],lastNum+1,MqttMsgTypeEnum_COMMENT_DYNAMIC];
                    BOOL resChange = [blockSelf.db executeUpdate:updateStr];
                    if (resChange == NO) {
                        NSLog(@"修改消息表动态失败");
                    }
                }
                
                
                /*********************************通知操作-动态********************************/
                /*
                 ↓
                 ↓
                 ↓
                 ↓
                 */
                NSLog(@"收到的评论消息:%@",dict);
                NSDictionary *dictionary = [NSDictionary dictionaryWithObject:[dict objectForKey:@"sender"] forKey:@"customerId"];
                [AFNetworkTool postJSONWithUrl:[NSString stringWithFormat:@"%@/customerManager/getCustomerInfoLatestByCustomerId.shtml",AliYunIndexPage] parameters:dictionary success:^(id responseObject) {
                    id json = [NSJSONSerialization JSONObjectWithData:responseObject options:NSJSONReadingMutableContainers error:nil];
                    NSDictionary *receiveDict = (NSDictionary *)json;
                    if ([receiveDict[@"state"] isEqual:@"success"]) {
                        NSDictionary *dataDict = [receiveDict objectForKey:@"customerInfoLatest"];
                        NSString * senderNickName = [NSString stringWithFormat:@"%@",[dataDict objectForKey:@"nickName"]];
                        NSString * localBody = [NSString stringWithFormat:@"%@评论了你的动态",senderNickName];
                        
                        NSMutableDictionary *dictM = [NSMutableDictionary dictionaryWithDictionary:dict];
                        [dictM setObject:localBody forKey:@"localBody"];
                        
                        [blockSelf sendLocalNotification:dictM];
                        
                    } else {
                        
                    }
                } fail:^{
                    NSLog(@"请求失败");
                    
                }];
                
                [ZHLNotificationCenter postNotificationName:SendMsgName object:dict];
                /*
                 ↑
                 ↑
                 ↑
                 ↑
                 */
                /*********************************通知操作-动态********************************/
                
                
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                if (blockSelf.messageBlock) {
                    blockSelf.messageBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                }
                
                return;
            }
            
            
            /*
             *
             *
             *
             *   判断本地设置选项-是否接收陌生人消息，若不接收，则判断是否为好友
             *
             *
             *
             *
             */
            NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
            BOOL isAcceptStranger = [userDefault boolForKey:@"isSearch"];//yes接收陌生人消息,no不接收
            BOOL isInFriendCache = YES;
            if (!isAcceptStranger) {
                //当设置不接收陌生人消息时,查看是否为好友
                if ([[NSUserDefaults standardUserDefaults]objectForKey:@"friendsList"]) {
                    NSArray * tempArray = [[NSUserDefaults standardUserDefaults]objectForKey:@"friendsList"];
                    NSMutableArray *arrayM = [FriendModel mj_objectArrayWithKeyValuesArray:tempArray];
                    for (FriendModel *model in arrayM) {
                        NSString *senderId = [NSString stringWithFormat:@"%@",model.id];
                        if ([[dict objectForKey:@"sender"] isEqualToString:senderId]) {
                            isInFriendCache = YES;
                            break;
                        }else{
                            isInFriendCache = NO;
                        }
                        if (arrayM.count == 0) {
                            isInFriendCache = NO;
                        }
                    }
                }else{
                    isInFriendCache = NO;
                }
                if (!isInFriendCache) {
                    //当不是好友时,不接收消息
                    NSArray *msgArray = dict[Mqtt_msg];
                    NSString *msgType = [NSString stringWithFormat:@"%@",dict[Mqtt_msgType]];
                    NSString *str = [NSString stringWithFormat:@"%@/customerFriendsControl/isFriendsByIds.shtml",AliYunIndexPage];
                    
                    NSURL *url = [NSURL URLWithString:str];
                    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
                    [request setHTTPMethod:@"POST"];
                    
                    NSDictionary *dataDict = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
                    NSDictionary *userInfoDict = dataDict[@"userInfo"];
                    NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
                    //
                    NSString *postStr = [NSString stringWithFormat:@"customerId=%@&frinedsId=%@",userIdStr,[NSString stringWithFormat:@"%@",[dict objectForKey:@"sender"]]];
                    [request setHTTPBody:[postStr dataUsingEncoding:NSUTF8StringEncoding]];
                    
                    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                    
                    //                        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjects:@[userIdStr,[NSString stringWithFormat:@"%@",[NSString stringWithFormat:@"%@",[dict objectForKey:@"sender"]]]] forKeys:@[@"customerId",@"friendsId"]];
                    //                        [AFNetworkTool postJSONWithUrl:[NSString stringWithFormat:@"%@/customerFriendsControl/isFriendsByIds.shtml",AliYunIndexPage] parameters:dict success:^(id responseObject) {
                    //                            
                    //                            id json = [NSJSONSerialization JSONObjectWithData:responseObject options:NSJSONReadingMutableContainers error:nil];
                    //                            NSDictionary *dict = (NSDictionary *)json;
                    //                            if ([dict[@"state"] isEqualToString:@"success"]) {
                    //                                self.isFriend = [NSString stringWithFormat:@"%@",[dict objectForKey:@"msg"]];
                    //                                [self.reloadViewDict setObject:self.isFriend forKey:@"isFriend"];
                    //                                
                    //                                self.personalView.reloadViewDict = self.reloadViewDict;
                    //                                
                    //                            }
                    //                        } fail:^{
                    //                            NSLog(@"请求错误");
                    //                        }];
                    
                    
                    
                    NSURLSession *session = [NSURLSession sharedSession];
                    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        if (error == nil) {
                            id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
                            NSDictionary *dataDict = (NSDictionary *)json;
                            if ([dataDict[@"state"] isEqualToString:@"success"]) {
                                NSString *isFriend = [NSString stringWithFormat:@"%@",[dataDict objectForKey:@"msg"]];
                                if ([isFriend isEqualToString:@"0"] || [isFriend isEqualToString:@"1"] || [isFriend isEqualToString:@"3"]) {
                                    if ([msgType isEqualToString:MqttMsgTypeEnum_FRIEND]) {
                                        if ([msgArray.firstObject isEqualToString:MqttFriendRelationTypeEnum_ADD] ||[msgArray.firstObject isEqualToString:MqttFriendRelationTypeEnum_AGREE]) {
                                            
                                        }else{
                                            return;
                                        }
                                    }
                                }
                            }
                            dispatch_semaphore_signal(semaphore);
                        }
                    }];
                    [dataTask resume];
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                }
            }
            
            NSString *createStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,dict[Mqtt_sender]]];
            //创建一张单聊表
            BOOL resTableOne = [blockSelf.db executeUpdate:createStr];
            if (resTableOne == NO) {
                NSLog(@"创建单聊表失败");
            }
            
            NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@",[NSString stringWithFormat:Table_Person_Format,dict[Mqtt_sender]]];
            int count = [blockSelf.db intForQuery:getCountStr];
            [dict setObject:[NSString stringWithFormat:@"%d",count+1] forKey:@"uid"];
            
            //msg字符串
            NSData *msgData = [NSJSONSerialization dataWithJSONObject:dict[Mqtt_msg] options:0 error:nil];
            NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
            
            //判断:普通消息&&oneBlock&&指针指向传入的ID
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msgStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            NSString *msgTypeStr = [NSString stringWithFormat:@"%@",dict[Mqtt_msgType]];
            if ((!(([msgTypeStr isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgTypeStr isEqualToString:MqttMsgTypeEnum_VOICE]||[msgTypeStr isEqualToString:MqttMsgTypeEnum_FRIEND])) && blockSelf.oneBlock && [[NSString stringWithFormat:@"%@",blockSelf.userIdFromPersonChat] isEqualToString:[NSString stringWithFormat:@"%@",dict[Mqtt_sender]]]) {
                //普通消息&&oneBlock&&指针指向传入的ID,将收到的消息直接按已读消息存入单聊记录
                
                [dict setObject:[NSString stringWithFormat:@"1"] forKey:@"isRead"];
                
                NSString *insertStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Person_Format,dict[Mqtt_sender]],dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],[NSString stringWithFormat:@"1"],[NSString stringWithFormat:MqttDbMessageStatusEnum_RECEIVE_SUCCESS]];
                BOOL res = [blockSelf.db executeUpdate:insertStr];
                if (res == NO) {
                    NSLog(@"添加一条单聊数据失败");
                }
            } else {
                //单聊记录中的未读消息
                
                [dict setObject:[NSString stringWithFormat:@"0"] forKey:@"isRead"];
                
                NSString *insertStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Person_Format,dict[Mqtt_sender]],dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],[NSString stringWithFormat:@"0"],[NSString stringWithFormat:MqttDbMessageStatusEnum_RECEIVE_SUCCESS]];
                BOOL res = [blockSelf.db executeUpdate:insertStr];
                if (res == NO) {
                    NSLog(@"添加一条单聊数据失败");
                }
            }
            //});
            
            //消息表
            //在线程中的数据库操作
            //dispatch_async([JayClientManager sharedClient].queue, ^{
            
            //如果消息表不存在，就创建一张消息表
            NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,nickName,sex,age,opposite,headImg data)"];
            BOOL resTableMsg = [blockSelf.db executeUpdate:createMessageTableStr];
            if (resTableMsg == NO) {
                NSLog(@"创建消息表失败");
            }
            
            //NSData *msgData = [NSJSONSerialization dataWithJSONObject:dict[Mqtt_msg] options:0 error:nil];
            //NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
            
            //查找消息表中是否已经有该条数据，有就在原有的那条数据中的msgNumber上+1，没有就创建一条数据
            FMResultSet* set = [blockSelf.db executeQuery:@"select * from Table_Message"];
            while ([set next]) {
                //通过opposite来判断是否已经存在该条消息数据
                NSString *oppositeStr = [set stringForColumn:@"opposite"];
                
                //已存在
                if ([oppositeStr isEqualToString:[NSString stringWithFormat:@"%@",dict[Mqtt_sender]]]) {
                    
                    _isExistMessage = YES;
                    
                    //判断:普通消息&&oneBlock&&指针指向传入的ID
                    NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msgStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
                    NSString *msgTypeStr = [NSString stringWithFormat:@"%@",dict[Mqtt_msgType]];
                    if (blockSelf.oneBlock && [[NSString stringWithFormat:@"%@",blockSelf.userIdFromPersonChat] isEqualToString:[NSString stringWithFormat:@"%@",dict[Mqtt_sender]]]) {
                        //int msgNum = [set intForColumn:@"msgNumber"];
                        //                            NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set sender='%@',receiver='%@',msgType='%@',chatType='%@',msg='%@',sendTime='%@',msgNumber=0 where opposite='%@'",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],dict[Mqtt_sender]];
                        BOOL resChange = [blockSelf.db executeUpdate:@"update Table_Message set sender=?,receiver=?,msgType=?,chatType=?,msg=?,sendTime=?,msgNumber=? where opposite=?",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@0,dict[Mqtt_sender]];
                        if (resChange == NO) {
                            NSLog(@"修改消息表失败");
                        }else{
                            NSLog(@"修改消息表成功");
                        }
                    } else {
                        int msgNum = [set intForColumn:@"msgNumber"];
                        NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set sender='%@',receiver='%@',msgType='%@',chatType='%@',msg='%@',sendTime='%@',msgNumber=%d where opposite='%@'",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],msgNum+1,dict[Mqtt_sender]];
                        BOOL resChange = [blockSelf.db executeUpdate:updateStr];
                        if (resChange == NO) {
                            NSLog(@"修改消息表失败");
                        }else{
                            NSLog(@"修改消息表成功");
                        }
                    }
                }
            }
            
            //不存在，增加一条消息数据
            if (_isExistMessage == NO) {
                
                NSString *str = [NSString stringWithFormat:@"%@/customerManager/getCustomerInfoLatestByCustomerId.shtml",AliYunIndexPage];
                
                NSURL *url = [NSURL URLWithString:str];
                NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
                [request setHTTPMethod:@"POST"];
                
                NSString *postStr = [NSString stringWithFormat:@"customerId=%@",dict[Mqtt_sender]];
                [request setHTTPBody:[postStr dataUsingEncoding:NSUTF8StringEncoding]];
                
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                NSURLSession *session = [NSURLSession sharedSession];
                NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    if (!error && data) {
                        id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
                        NSDictionary *responseDict = (NSDictionary *)json;
                        NSDictionary *customerInfoLatest = responseDict[@"customerInfoLatest"];
                        NSString *nickName = [NSString stringWithFormat:@"%@",customerInfoLatest[@"nickName"]];
                        NSString *sex = [NSString stringWithFormat:@"%@",customerInfoLatest[@"sex"]];
                        NSString *age = [NSString stringWithFormat:@"%@",customerInfoLatest[@"age"]];
                        if (!age || [age isEqualToString:@"(null)"]) {
                            age = @"0";
                        }
                        NSString *headImg = [NSString stringWithFormat:@"%@",customerInfoLatest[@"headImg"]];
                        
                        NSURL *headImgUrl = [NSURL URLWithString:headImg];
                        NSURLSessionDataTask *imageTask = [session dataTaskWithURL:headImgUrl completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            if (!error && data) {
                                BOOL resAddMsg = [blockSelf.db executeUpdate:@"insert into Table_Message(sender,receiver,msgType,chatType,msg,sendTime,msgNumber,nickName,sex,age,opposite,headImg) values(?,?,?,?,?,?,?,?,?,?,?,?)",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@1,nickName,sex,age,dict[Mqtt_sender],data];
                                if (resAddMsg == NO) {
                                    NSLog(@"添加一条消息数据失败");
                                }else{
                                    NSLog(@"添加一条消息数据成功");
                                }
                                
                                
                                
                            }
                            dispatch_semaphore_signal(semaphore);
                        }];
                        [imageTask resume];
                        
                    }else{
                        //                            BOOL resAddMsg = [blockSelf.db executeUpdate:@"insert into Table_Message(sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite) values(?,?,?,?,?,?,?,?)",dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@1,dict[Mqtt_sender]];
                        //                            if (resAddMsg == NO) {
                        //                                NSLog(@"添加一条消息数据失败");
                        //                            }else{
                        //                                NSLog(@"添加一条消息数据成功");
                        //                            }
                        dispatch_semaphore_signal(semaphore);
                        
                    }
                }];
                [dataTask resume];
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                
                
            }
            
            _isExistMessage = NO;
            //});
            
            //消息接收成功
            [dict setObject:MqttDbMessageStatusEnum_RECEIVE_SUCCESS forKey:@"messageStatus"];
            
            
            /*********************************通知操作-单聊********************************/
            /*
             ↓
             ↓
             ↓
             ↓
             */
            NSLog(@"jie收到的消息:%@",dict);
            NSMutableString * messageStr = [NSMutableString string];
            
            if ([[dict objectForKey:@"msgType"] isEqualToString:MqttMsgTypeEnum_STANDARD]) {
                blockSelf.msgArray = [dict objectForKey:@"msg"];
                for (id value in [dict objectForKey:@"msg"]) {
                    messageStr = [NSMutableString stringWithFormat:@"%@%@",messageStr,value];
                }
            }
            
            NSDictionary *dictionary = [NSDictionary dictionaryWithObject:[dict objectForKey:@"sender"] forKey:@"customerId"];
            [AFNetworkTool postJSONWithUrl:[NSString stringWithFormat:@"%@/customerManager/getCustomerInfoLatestByCustomerId.shtml",AliYunIndexPage] parameters:dictionary success:^(id responseObject) {
                id json = [NSJSONSerialization JSONObjectWithData:responseObject options:NSJSONReadingMutableContainers error:nil];
                NSDictionary *receiveDict = (NSDictionary *)json;
                if ([receiveDict[@"state"] isEqual:@"success"]) {
                    NSDictionary *dataDict = [receiveDict objectForKey:@"customerInfoLatest"];
                    NSString * senderNickName = [NSString stringWithFormat:@"%@",[dataDict objectForKey:@"nickName"]];
                    NSString * localBody = [NSString stringWithFormat:@"%@:%@",senderNickName,messageStr];
                    
                    NSMutableDictionary *dictM = [NSMutableDictionary dictionaryWithDictionary:dict];
                    [dictM setObject:localBody forKey:@"localBody"];
                    [dictM setObject:senderNickName forKey:@"nickName"];
                    [dictM setObject:messageStr forKey:@"messageStr"];
                    [blockSelf sendLocalNotification:dictM];
                } else {
                }
            } fail:^{
                NSLog(@"请求失败");
                
            }];
            
            [ZHLNotificationCenter postNotificationName:SendMsgName object:dict];
            
            /*
             ↑
             ↑
             ↑
             ↑
             */
            /*********************************通知操作-单聊********************************/
            
            
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
            if (blockSelf.oneBlock) {
                if ([[NSString stringWithFormat:@"%@",dict[Mqtt_sender]] isEqualToString:blockSelf.userIdFromPersonChat]) {
                    blockSelf.oneBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                }
            } else {
                if (blockSelf.messageBlock) {
                    blockSelf.messageBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                }
            }
        }
        
        if ([[NSString stringWithFormat:@"%@",dict[Mqtt_chatType]] isEqualToString:[NSString stringWithFormat:MqttChatTypeEnum_MULTI_CHAT]]) {
            //收到的是群聊的消息
            
            if ([[NSUserDefaults standardUserDefaults] objectForKey:@"userData"]) {
                NSDictionary *dictFromDefaults = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
                NSDictionary *userInfoDict = dictFromDefaults[@"userInfo"];
                NSString *userIdStr = [NSString stringWithFormat:@"%@",userInfoDict[@"id"]];
                //登陆用户自己发的群聊消息
                if ([[NSString stringWithFormat:@"%@",dict[Mqtt_sender]] isEqualToString:userIdStr]) {
                    return;
                }
            }
            
            if ([[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:[NSString stringWithFormat:MqttMsgTypeEnum_GAME_NOTIFI]]) {
                NSArray *msgArr = dict[Mqtt_msg];
                if ([msgArr.firstObject isEqualToString:MqttGameMsgTypeEnum_INITIATOR]) {
                    return;
                }
                if (![msgArr.firstObject isEqualToString:MqttGameMsgTypeEnum_INITIATOR_RESULT]) {
                    if (![msgArr[2] isEqualToString:blockSelf.gameIdFromGroupChat]) {
                        return;
                    }
                    if ([msgArr.firstObject isEqualToString:MqttGameMsgTypeEnum_EXIT]) {
                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                        
                        if (blockSelf.groupBlock && [[NSString stringWithFormat:@"%@",dict[Mqtt_receiver]] isEqualToString:[NSString stringWithFormat:@"%@",blockSelf.groupIdFromGroupChat]]) {
                            blockSelf.groupBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                        }
                        
                        
                        return;
                    }
                    
                }
                
            }
            
            if ([[NSString stringWithFormat:@"%@",dict[Mqtt_sender]] isEqualToString:@"1099"] && [[NSString stringWithFormat:@"%@",dict[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_GAME_NOTIFI]) {
                
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                if (blockSelf.groupBlock && [[NSString stringWithFormat:@"%@",dict[Mqtt_receiver]] isEqualToString:[NSString stringWithFormat:@"%@",blockSelf.groupIdFromGroupChat]]) {
                    blockSelf.groupBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                }
                
                return;
            }
            
            //在线程中的数据库操作
            //dispatch_async([JayClientManager sharedClient].queue, ^{
            
            //创建一张群聊表
            NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]]];
            BOOL resTable = [blockSelf.db executeUpdate:createGroupTableStr];
            if (resTable == NO) {
                NSLog(@"创建群聊表失败");
            }
            
            //                //判断字段是否存在
            //                if ([[JayClientManager sharedClient].db columnExists:@"isRead" inTableWithName:[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]]]) {
            //                    NSString *update = [NSString stringWithFormat:@"UPDATE %@ SET %@=? WHERE %@ = '%@'",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]],@"isRead",@"receiver",dict[Mqtt_receiver]];
            //                    [[JayClientManager sharedClient].db executeUpdate:update];
            //                }else{
            //                    NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD %@ text",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]],@"isRead"];
            //                    [[JayClientManager sharedClient].db executeUpdate:sql];
            //                    NSString *update = [NSString stringWithFormat:@"UPDATE %@ SET %@=? WHERE %@ = '%@'",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]],@"isRead",@"receiver",dict[Mqtt_receiver]];
            //                    [[JayClientManager sharedClient].db executeUpdate:update];
            //                }
            
            NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]]];
            int count = [blockSelf.db intForQuery:getCountStr];
            [dict setObject:[NSString stringWithFormat:@"%d",count+1] forKey:@"uid"];
            
            NSData *msgData = [NSJSONSerialization dataWithJSONObject:dict[Mqtt_msg] options:0 error:nil];
            NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
            
            //判断:普通消息&&oneBlock&&指针指向传入的ID
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msgStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            NSString *msgTypeStr = [NSString stringWithFormat:@"%@",dict[Mqtt_msgType]];
            if ((!(([msgTypeStr isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgTypeStr isEqualToString:MqttMsgTypeEnum_VOICE])) && blockSelf.groupBlock && [[NSString stringWithFormat:@"%@",blockSelf.groupIdFromGroupChat] isEqualToString:[NSString stringWithFormat:@"%@",dict[Mqtt_receiver]]]) {
                
                [dict setObject:[NSString stringWithFormat:@"1"] forKey:@"isRead"];
                
                //添加一条群聊数据
                NSString *addGroupMessageStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]],dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@"1",MqttDbMessageStatusEnum_RECEIVE_SUCCESS];
                BOOL res = [blockSelf.db executeUpdate:addGroupMessageStr];
                if (res == NO) {
                    NSLog(@"添加一条群聊数据失败");
                }
            } else {
                
                NSDictionary *dictFromUserDefaults = [[NSUserDefaults standardUserDefaults] objectForKey:@"userData"];
                NSDictionary *userInfoDictFromUserDefaults = dictFromUserDefaults[@"userInfo"];
                NSString *userIdStrFromUserDefaults = [NSString stringWithFormat:@"%@",userInfoDictFromUserDefaults[@"id"]];
                if ([[NSString stringWithFormat:@"%@",dict[Mqtt_sender]] isEqualToString:userIdStrFromUserDefaults]) {
                    //自己发的
                    [dict setObject:[NSString stringWithFormat:@"1"] forKey:@"isRead"];
                } else {
                    [dict setObject:[NSString stringWithFormat:@"0"] forKey:@"isRead"];
                }
                
                //添加一条群聊数据
                NSString *addGroupMessageStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Group_Format,dict[Mqtt_receiver]],dict[Mqtt_sender],dict[Mqtt_receiver],dict[Mqtt_msgType],dict[Mqtt_chatType],msgStr,dict[Mqtt_sendTime],@"0",MqttDbMessageStatusEnum_RECEIVE_SUCCESS];
                BOOL res = [blockSelf.db executeUpdate:addGroupMessageStr];
                if (res == NO) {
                    NSLog(@"添加一条群聊数据失败");
                }
            }
            //});
            
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
            
            //                NSLog(@"receiver = %@,groupIdFromGroupChat = %@",dict[Mqtt_receiver],[JayClientManager sharedClient].groupIdFromGroupChat);
            //                
            //                if (![JayClientManager sharedClient].groupBlock) {
            //                    NSLog(@"error = groupBlock");
            //                }
            //                
            //                if (![[NSString stringWithFormat:@"%@",dict[Mqtt_receiver]] isEqualToString:[NSString stringWithFormat:@"%@",[JayClientManager sharedClient].groupIdFromGroupChat]]) {
            //                    NSLog(@"error = dict[Mqtt_receiver]---groupIdFromGroupChat");
            //                }
            
            if (blockSelf.groupBlock && [[NSString stringWithFormat:@"%@",dict[Mqtt_receiver]] isEqualToString:[NSString stringWithFormat:@"%@",blockSelf.groupIdFromGroupChat]]) {
                blockSelf.groupBlock([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
            }
        }
        
    });
}

//传入要发送的字典和shopStr,返回主题topStr
- (NSString *)getTopStrFromSendDictionary:(NSMutableDictionary *)sendDictionary andShopStr:(NSString *)shopStr
{
    NSString *topStr;
    switch ([sendDictionary[Mqtt_msgType] intValue]) {
        case 0:// 普通消息（文本消息、表情、文本表情混合）
            topStr = [NSString stringWithFormat:STANDARD_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 1:// 图片
            topStr = [NSString stringWithFormat:PHOTO_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 2:// 语音
            topStr = [NSString stringWithFormat:VOICE_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 3:// 好友相关
            topStr = [NSString stringWithFormat:FRIEND_MANAGER_CHAT_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 4:// 游戏
            topStr = [NSString stringWithFormat:STANDARD_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 5:// 红包
            topStr = [NSString stringWithFormat:RED_PACKETS_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 6:// 聊天动作
            topStr = [NSString stringWithFormat:ACTION_CHAT_MSG_TOPIC_FORMAT,shopStr];
            break;
        case 7:// 在线状态
            topStr = [NSString stringWithFormat:STATE_CHAT_NOTIFI_TOPIC_FORMAT,shopStr];
            break;
        case 8:// 系统通知
            topStr = [NSString stringWithFormat:SYS_NOTIFI_TOPIC_FORMAT];
            break;
        case 9:// 动态评论
            topStr = [NSString stringWithFormat:COMMENT_DYNAMIC_TOPIC_FORMAT,shopStr];
            break;
        case 10:// 礼物？
            topStr = [NSString stringWithFormat:@"%@/chat",shopStr];
            break;
        default:
            break;
    }
    
    return topStr;
}

//获取群聊历史记录，传入群ID
/*
 * 该方法在线程中调用，请使用如下线程
 * dispatch_async([JayClientManager sharedClient].queue, ^{
 *
 *     dispatch_async(dispatch_get_main_queue(), ^(){
 *         //这里是主线程，在此处更新界面
 *     });
 * });
 */
-(void)getHistoryOfGroupWithGroupName:(NSString *)groupName success:(void(^)(NSArray * history))handle{
    __block NSMutableArray *historyMuArr = [NSMutableArray new];
    dispatch_async([JayClientManager sharedClient].queue, ^{
        //创建一张群聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,groupName]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建群聊表失败");
        }
        
        //查询群聊表内所有数据
        NSString *searchStr = [NSString stringWithFormat:@"select * from %@ order by uid desc limit 6",[NSString stringWithFormat:Table_Group_Format,groupName]];
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:searchStr];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            NSString *sender = [set stringForColumn:@"sender"];
            NSString *receiver = [set stringForColumn:@"receiver"];
            NSString *msgType = [set stringForColumn:@"msgType"];
            NSString *chatType = [set stringForColumn:@"chatType"];
            NSString *msg = [set stringForColumn:@"msg"];
            NSString *sendTime = [set stringForColumn:@"sendTime"];
            NSString *isRead = [set stringForColumn:@"isRead"];
            NSString *messageStatus = [set stringForColumn:@"messageStatus"];
            
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            
            if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE])) {
                //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
                
                if ([isRead isEqualToString:@"0"]) {
                    NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Group_Format,groupName],[NSString stringWithFormat:@"1"],uid];
                    BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
                    if (resChange == NO) {
                        NSLog(@"修改常规消息已读状态失败");
                    }
                }
                
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            } else {
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            }
        }
        
        historyMuArr = (NSMutableArray *)[[historyMuArr reverseObjectEnumerator] allObjects];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(historyMuArr);
        });
    });
}
//获取单聊历史记录，传入对方的用户ID
/*
 * 该方法在线程中调用，请使用如下线程
 * dispatch_async([JayClientManager sharedClient].queue, ^{
 *
 *     dispatch_async(dispatch_get_main_queue(), ^(){
 *         //这里是主线程，在此处更新界面
 *     });
 * });
 */
-(void)getHistoryOfPersonWithSenderName:(NSString *)senderName success:(void(^)(NSArray * history))handle{
    
    __block NSMutableArray *historyMuArr = [NSMutableArray new];
    dispatch_async([JayClientManager sharedClient].queue, ^{
        
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,senderName]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建单聊表失败");
        }
        
        //查询单聊表内所有数据
        NSString *searchStr = [NSString stringWithFormat:@"select * from %@ order by uid desc limit 6",[NSString stringWithFormat:Table_Person_Format,senderName]];
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:searchStr];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            NSString *sender = [set stringForColumn:@"sender"];
            NSString *receiver = [set stringForColumn:@"receiver"];
            NSString *msgType = [set stringForColumn:@"msgType"];
            NSString *chatType = [set stringForColumn:@"chatType"];
            NSString *msg = [set stringForColumn:@"msg"];
            NSString *sendTime = [set stringForColumn:@"sendTime"];
            NSString *isRead = [set stringForColumn:@"isRead"];
            NSString *messageStatus = [set stringForColumn:@"messageStatus"];
            
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            
            if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE]||[msgType isEqualToString:MqttMsgTypeEnum_FRIEND])) {
                //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
                
                if ([isRead isEqualToString:@"0"]) {
                    NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Person_Format,senderName],[NSString stringWithFormat:@"1"],uid];
                    BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
                    if (resChange == NO) {
                        NSLog(@"修改常规消息已读状态失败");
                    }
                }
                
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            } else {
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            }
        }
        
        //如果消息表不存在，就创建一张消息表
        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
        BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
        if (resTableMsg == NO) {
            NSLog(@"创建消息表失败");
        }
        
        NSString *isExistStr = [NSString stringWithFormat:@"select count(*) from Table_Message where opposite='%@'",senderName];
        int senderNum = [[JayClientManager sharedClient].db intForQuery:isExistStr];
        
        if (senderNum != 0) {
            //消息表中已存在该ID对应的数据
            NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set msgNumber=0 where opposite='%@'",senderName];
            BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
            if (resChange == NO) {
                NSLog(@"修改消息表失败");
            }
        }
        
        historyMuArr = (NSMutableArray *)[[historyMuArr reverseObjectEnumerator] allObjects];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [ZHLNotificationCenter postNotificationName:ReadMessage object:nil];
            handle(historyMuArr);
        });
    });
    
}


//删除群聊记录，传入群ID
- (void)removeGroupHistoryWithGroupName:(NSString *)groupName
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSString *removeStr = [NSString stringWithFormat:@"drop table if exists %@",[NSString stringWithFormat:Table_Group_Format,groupName]];
        [[JayClientManager sharedClient].db executeUpdate:removeStr];
        dispatch_async(dispatch_get_main_queue(), ^{
            
        });
    });
}

//删除单聊记录，传入对方用户ID
- (void)removePersonHistoryWithPersonName:(NSString *)personName
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSString *removeStr = [NSString stringWithFormat:@"drop table if exists %@",[NSString stringWithFormat:Table_Person_Format,personName]];
        [[JayClientManager sharedClient].db executeUpdate:removeStr];
        dispatch_async(dispatch_get_main_queue(), ^{
            
        });
    });
}

//删除一条消息记录，传入对方用户ID
- (void)removeRecordFromMessageListWithUserID:(NSString *)userID
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSString *removeStr = [NSString stringWithFormat:@"delete from Table_Message where opposite='%@'",userID];
        [[JayClientManager sharedClient].db executeUpdate:removeStr];
        dispatch_async(dispatch_get_main_queue(), ^{
            
        });
    });
}

//获取消息列表
-(void)getMessageList:(void(^)(NSArray * messageList))handle{
    NSMutableArray *historyMuArr = [NSMutableArray array];
    __block JayClientManager *blockSelf = self;
    dispatch_async(blockSelf.queue, ^{
        //如果消息表不存在，就创建一张消息表
        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,nickName,sex,age,opposite,headImg data)"];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
        if (resTable == NO) {
            NSLog(@"创建消息表失败");
        }
        //遍历消息表
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:@"select * from Table_Message"];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            NSString *sender = [set stringForColumn:@"sender"];
            NSString *receiver = [set stringForColumn:@"receiver"];
            NSString *msgType = [set stringForColumn:@"msgType"];
            NSString *chatType = [set stringForColumn:@"chatType"];
            NSString *msg = [set stringForColumn:@"msg"];
            NSString *sendTime = [set stringForColumn:@"sendTime"];
            int msgNum = [set intForColumn:@"msgNumber"];
            NSString *nickName = [set stringForColumn:@"nickName"];
            NSString *sex = [set stringForColumn:@"sex"];
            NSString *age = [set stringForColumn:@"age"];
            NSString *opposite = [set stringForColumn:@"opposite"];
            NSData *headImg = [set dataForColumn:@"headImg"];
            NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"%d",msgNum],@"msgNumber",nickName,@"nickName",sex,@"sex",age,@"age",opposite,@"opposite",headImg,@"headImg", nil];
            [historyMuArr addObject:dict];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(historyMuArr);
        });
        
    });
    
}
//获取动态列表
- (NSMutableArray *)getDynamicList
{
    NSMutableArray *historyMuArr = [NSMutableArray array];
    
    //如果动态表不存在，就创建一张动态表
    NSString *createDynamicTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead)",Table_Dynamic_Format];
    BOOL resDynamicTableMsg = [[JayClientManager sharedClient].db executeUpdate:createDynamicTableStr];
    if (resDynamicTableMsg == NO) {
        NSLog(@"创建动态表失败");
    }
    
    //遍历动态表
    FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:@"select * from Table_Dynamic"];
    while ([set next]) {
        int uid = [set intForColumn:@"uid"];
        NSString *sender = [set stringForColumn:@"sender"];
        NSString *receiver = [set stringForColumn:@"receiver"];
        NSString *msgType = [set stringForColumn:@"msgType"];
        NSString *chatType = [set stringForColumn:@"chatType"];
        NSString *msg = [set stringForColumn:@"msg"];
        NSString *sendTime = [set stringForColumn:@"sendTime"];
        NSString *isRead = [set stringForColumn:@"isRead"];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead", nil];
        [historyMuArr addObject:dict];
    }
    
    //如果消息表不存在，就创建一张消息表
    NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
    BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
    if (resTableMsg == NO) {
        NSLog(@"创建消息表失败");
    }
    
    NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set msgNumber=0 where msgType='%@'",MqttMsgTypeEnum_COMMENT_DYNAMIC];
    BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
    if (resChange == NO) {
        NSLog(@"修改消息表动态msgNumber为0失败");
    }
    
    return historyMuArr;
}
- (void)getDynamicList:(void(^)(NSArray * dynamicList))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSMutableArray * history = [[JayClientManager sharedClient] getDynamicList];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(history);
        });
    });
}

/*****************************   聊天记录分页加载   ******************************/
//根据传入的uid获取num条群聊记录，本方法提供uid向上num条数据
- (void)getUpPageHistoryOfGroupWithGroupName:(NSString *)groupName andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * History))handle{
    NSMutableArray *historyMuArr = [NSMutableArray array];
    __block JayClientManager *blockSelf = self;
    __block int blockNum = num;
    dispatch_async(blockSelf.queue, ^{
        //创建一张群聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,groupName]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建群聊表失败");
        }
        
        if ([uidString intValue] <= blockNum) {
            blockNum = [uidString intValue] - 1;
        }
        
        //查询群聊表内所有数据
        NSString *searchStr = [NSString stringWithFormat:@"select * from %@ where uid >= %d",[NSString stringWithFormat:Table_Group_Format,groupName],[uidString intValue]-num];
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:searchStr];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            NSString *sender = [set stringForColumn:@"sender"];
            NSString *receiver = [set stringForColumn:@"receiver"];
            NSString *msgType = [set stringForColumn:@"msgType"];
            NSString *chatType = [set stringForColumn:@"chatType"];
            NSString *msg = [set stringForColumn:@"msg"];
            NSString *sendTime = [set stringForColumn:@"sendTime"];
            NSString *isRead = [set stringForColumn:@"isRead"];
            NSString *messageStatus = [set stringForColumn:@"messageStatus"];
            
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            
            if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE])) {
                //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
                
                if ([isRead isEqualToString:@"0"]) {
                    NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Group_Format,groupName],[NSString stringWithFormat:@"1"],uid];
                    BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
                    if (resChange == NO) {
                        NSLog(@"修改常规消息已读状态失败");
                    }
                }
                
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            } else {
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(historyMuArr);
        });
        
    });
}


//根据传入的uid获取num条群聊记录，本方法提供uid向下num条数据
- (NSMutableArray *)getDownPageHistoryOfGroupWithGroupName:(NSString *)groupName andUID:(NSString *)uidString andNumbers:(int)num
{
    NSMutableArray *historyMuArr = [NSMutableArray array];
    
    //创建一张群聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,groupName]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建群聊表失败");
    }
    
    //查询群聊表内所有数据
    NSString *searchStr = [NSString stringWithFormat:@"select * from %@ where uid <= %d and uid > %d",[NSString stringWithFormat:Table_Group_Format,groupName],[uidString intValue]+num,[uidString intValue]];
    FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:searchStr];
    while ([set next]) {
        int uid = [set intForColumn:@"uid"];
        NSString *sender = [set stringForColumn:@"sender"];
        NSString *receiver = [set stringForColumn:@"receiver"];
        NSString *msgType = [set stringForColumn:@"msgType"];
        NSString *chatType = [set stringForColumn:@"chatType"];
        NSString *msg = [set stringForColumn:@"msg"];
        NSString *sendTime = [set stringForColumn:@"sendTime"];
        NSString *isRead = [set stringForColumn:@"isRead"];
        NSString *messageStatus = [set stringForColumn:@"messageStatus"];
        
        NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
        
        if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE])) {
            //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
            
            if ([isRead isEqualToString:@"0"]) {
                NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Group_Format,groupName],[NSString stringWithFormat:@"1"],uid];
                BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
                if (resChange == NO) {
                    NSLog(@"修改常规消息已读状态失败");
                }
            }
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
            [historyMuArr addObject:dict];
        } else {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
            [historyMuArr addObject:dict];
        }
    }
    
    return historyMuArr;
}
- (void)getDownPageHistoryOfGroupWithGroupName:(NSString *)groupName andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * history))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSMutableArray * history = [[JayClientManager sharedClient] getDownPageHistoryOfGroupWithGroupName:groupName andUID:uidString andNumbers:num];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(history);
        });
    });
}

//根据传入的uid获取num条单聊记录，本方法提供uid向上num条数据
- (void)getUpPageHistoryOfPersonWithUserID:(NSString *)userID andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * History))handle{
    NSMutableArray * historyMuArr = [NSMutableArray array];
    __block JayClientManager *blockSelf = self;
    __block int blockNum = num;
    dispatch_async(blockSelf.queue, ^{
        //创建一张单聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,userID]];
        BOOL resTable = [blockSelf.db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建单聊表失败");
        }
        
        if ([uidString intValue] <= blockNum) {
            blockNum = [uidString intValue] - 1;
        }
        
        //查询单聊表内所有数据
        NSString *searchStr = [NSString stringWithFormat:@"select * from %@ where uid >= %d",[NSString stringWithFormat:Table_Person_Format,userID],[uidString intValue]-num];
        FMResultSet* set = [blockSelf.db executeQuery:searchStr];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            NSString *sender = [set stringForColumn:@"sender"];
            NSString *receiver = [set stringForColumn:@"receiver"];
            NSString *msgType = [set stringForColumn:@"msgType"];
            NSString *chatType = [set stringForColumn:@"chatType"];
            NSString *msg = [set stringForColumn:@"msg"];
            NSString *sendTime = [set stringForColumn:@"sendTime"];
            NSString *isRead = [set stringForColumn:@"isRead"];
            NSString *messageStatus = [set stringForColumn:@"messageStatus"];
            
            NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
            
            if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE])) {
                //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
                
                if ([isRead isEqualToString:@"0"]) {
                    NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Person_Format,userID],[NSString stringWithFormat:@"1"],uid];
                    BOOL resChange = [blockSelf.db executeUpdate:updateStr];
                    if (resChange == NO) {
                        NSLog(@"修改常规消息已读状态失败");
                    }
                }
                
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            } else {
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
                [historyMuArr addObject:dict];
            }
        }
        
        //如果消息表不存在，就创建一张消息表
        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
        BOOL resTableMsg = [blockSelf.db executeUpdate:createMessageTableStr];
        if (resTableMsg == NO) {
            NSLog(@"创建消息表失败");
        }
        
        NSString *isExistStr = [NSString stringWithFormat:@"select count(*) from Table_Message where opposite='%@'",userID];
        int senderNum = [blockSelf.db intForQuery:isExistStr];
        
        if (senderNum != 0) {
            //消息表中已存在该ID对应的数据
            NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set msgNumber=0 where opposite='%@'",userID];
            BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
            if (resChange == NO) {
                NSLog(@"修改消息表失败");
            }
        }
        
        [ZHLNotificationCenter postNotificationName:ReadMessage object:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(historyMuArr);
        });
    });
    
}





//根据传入的uid获取num条单聊记录，本方法提供uid向下num条数据
- (NSMutableArray *)getDownPageHistoryOfPersonWithUserID:(NSString *)userID andUID:(NSString *)uidString andNumbers:(int)num
{
    NSMutableArray *historyMuArr = [NSMutableArray array];
    
    //创建一张单聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,userID]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建单聊表失败");
    }
    
    //查询单聊表内所有数据
    NSString *searchStr = [NSString stringWithFormat:@"select * from %@ where uid <= %d and uid > %d",[NSString stringWithFormat:Table_Person_Format,userID],[uidString intValue]+num,[uidString intValue]];
    FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:searchStr];
    while ([set next]) {
        int uid = [set intForColumn:@"uid"];
        NSString *sender = [set stringForColumn:@"sender"];
        NSString *receiver = [set stringForColumn:@"receiver"];
        NSString *msgType = [set stringForColumn:@"msgType"];
        NSString *chatType = [set stringForColumn:@"chatType"];
        NSString *msg = [set stringForColumn:@"msg"];
        NSString *sendTime = [set stringForColumn:@"sendTime"];
        NSString *isRead = [set stringForColumn:@"isRead"];
        NSString *messageStatus = [set stringForColumn:@"messageStatus"];
        
        NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
        
        if (!(([msgType isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE])||[msgType isEqualToString:MqttMsgTypeEnum_VOICE])) {
            //常规消息类型，直接将数据库中的未读状态变为已读，并添加到要返回的数组中
            
            if ([isRead isEqualToString:@"0"]) {
                NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%d",[NSString stringWithFormat:Table_Person_Format,userID],[NSString stringWithFormat:@"1"],uid];
                BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
                if (resChange == NO) {
                    NSLog(@"修改常规消息已读状态失败");
                }
            }
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",[NSString stringWithFormat:@"1"],@"isRead",messageStatus,@"messageStatus", nil];
            [historyMuArr addObject:dict];
        } else {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d",uid],@"uid",sender,@"sender",receiver,@"receiver",msgType,@"msgType",chatType,@"chatType",msg,@"msg",sendTime,@"sendTime",isRead,@"isRead",messageStatus,@"messageStatus", nil];
            [historyMuArr addObject:dict];
        }
    }
    
    //如果消息表不存在，就创建一张消息表
    NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
    BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
    if (resTableMsg == NO) {
        NSLog(@"创建消息表失败");
    }
    
    NSString *isExistStr = [NSString stringWithFormat:@"select count(*) from Table_Message where opposite='%@'",userID];
    int senderNum = [[JayClientManager sharedClient].db intForQuery:isExistStr];
    
    if (senderNum != 0) {
        //消息表中已存在该ID对应的数据
        NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set msgNumber=0 where opposite='%@'",userID];
        BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
        if (resChange == NO) {
            NSLog(@"修改消息表失败");
        }
    }
    
    return historyMuArr;
}
- (void)getDownPageHistoryOfPersonWithUserID:(NSString *)userID andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * history))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        NSMutableArray * history = [[JayClientManager sharedClient] getDownPageHistoryOfPersonWithUserID:userID andUID:uidString andNumbers:num];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(history);
        });
    });
}

//在线程中调用该方法
//dispatch_async([JayClientManager sharedClient].queue, ^{
//});
//单人消息发送时调用,将消息存入数据库,返回uid
- (int)messageToPersonSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus
{
    
    NSString *createStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,sendDictionary[Mqtt_receiver]]];
    //创建一张单聊表
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createStr];
    if (resTable == NO) {
        NSLog(@"创建单聊表失败");
    }
    
    NSData *msgData = [NSJSONSerialization dataWithJSONObject:sendDictionary[Mqtt_msg] options:0 error:nil];
    NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
    NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msgStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
    
    int isRead = 1;
    
    if ([[NSString stringWithFormat:@"%@",sendDictionary[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE]) {
        isRead = 0;
    }
    if ([[NSString stringWithFormat:@"%@",sendDictionary[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_FRIEND]&&[afterReadStr isEqualToString:MqttFriendRelationTypeEnum_ADD] && msgArr.count == 1) {
        return 0;
    }
    NSString *insertStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Person_Format,sendDictionary[Mqtt_receiver]],sendDictionary[Mqtt_sender],sendDictionary[Mqtt_receiver],sendDictionary[Mqtt_msgType],sendDictionary[Mqtt_chatType],msgStr,sendDictionary[Mqtt_sendTime],[NSString stringWithFormat:@"%d",isRead],messageStatus];
    BOOL res = [[JayClientManager sharedClient].db executeUpdate:insertStr];
    if (res == NO) {
        NSLog(@"添加一条单聊数据失败");
        return 0;
    }
    NSString *returnStr = [NSString stringWithFormat:@"SELECT seq FROM sqlite_sequence WHERE name= '%@' LIMIT 1",[NSString stringWithFormat:Table_Person_Format,sendDictionary[Mqtt_receiver]]];
    int returnInt = [[JayClientManager sharedClient].db intForQuery:returnStr];
    
    //如果消息表不存在，就创建一张消息表
    NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber,opposite)"];
    BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
    if (resTableMsg == NO) {
        NSLog(@"创建消息表失败");
    }
    if ([sendDictionary[Mqtt_msgType] isEqualToString:MqttMsgTypeEnum_FRIEND] && [msgArr.firstObject isEqualToString:MqttFriendRelationTypeEnum_ADD]) {
        return returnInt;
    }
    NSString *isExistStr = [NSString stringWithFormat:@"select count(*) from Table_Message where opposite='%@'",sendDictionary[Mqtt_receiver]];
    int senderNum = [[JayClientManager sharedClient].db intForQuery:isExistStr];
    
    if (senderNum == 0) {
        __weak JayClientManager *blockSelf = self;
        
        NSString *str = [NSString stringWithFormat:@"%@/customerManager/getCustomerInfoLatestByCustomerId.shtml",AliYunIndexPage];
        
        NSURL *url = [NSURL URLWithString:str];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
        [request setHTTPMethod:@"POST"];
        
        NSString *postStr = [NSString stringWithFormat:@"customerId=%@",sendDictionary[Mqtt_receiver]];
        [request setHTTPBody:[postStr dataUsingEncoding:NSUTF8StringEncoding]];
        
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && data) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
                NSDictionary *responseDict = (NSDictionary *)json;
                NSDictionary *customerInfoLatest = responseDict[@"customerInfoLatest"];
                NSString *nickName = [NSString stringWithFormat:@"%@",customerInfoLatest[@"nickName"]];
                NSString *sex = [NSString stringWithFormat:@"%@",customerInfoLatest[@"sex"]];
                NSString *age = [NSString stringWithFormat:@"%@",customerInfoLatest[@"age"]];
                if (!age || [age isEqualToString:@"(null)"]) {
                    age = @"0";
                }
                NSString *headImg = [NSString stringWithFormat:@"%@",customerInfoLatest[@"headImg"]];
                
                NSURL *headImgUrl = [NSURL URLWithString:headImg];
                NSURLSessionDataTask *imageTask = [session dataTaskWithURL:headImgUrl completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    if (!error && data) {
                        BOOL resAddMsg = [blockSelf.db executeUpdate:@"insert into Table_Message(sender,receiver,msgType,chatType,msg,sendTime,msgNumber,nickName,sex,age,opposite,headImg) values(?,?,?,?,?,?,?,?,?,?,?,?)",sendDictionary[Mqtt_sender],sendDictionary[Mqtt_receiver],sendDictionary[Mqtt_msgType],sendDictionary[Mqtt_chatType],msgStr,sendDictionary[Mqtt_sendTime],@0,nickName,sex,age,sendDictionary[Mqtt_receiver],data];
                        if (resAddMsg == NO) {
                            NSLog(@"添加一条消息数据失败");
                        }else{
                            NSLog(@"添加一条消息数据成功");
                        }
                        
                        
                        
                    }
                    dispatch_semaphore_signal(semaphore);
                }];
                [imageTask resume];
                
            }else{
                dispatch_semaphore_signal(semaphore);
                
            }
        }];
        [dataTask resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        
        
        
        
    } else {
        //消息表中已存在该ID对应的数据
        NSString *updateStr = [NSString stringWithFormat:@"update Table_Message set sender='%@',receiver='%@',msgType='%@',chatType='%@',msg='%@',sendTime='%@',msgNumber=0 where opposite='%@'",sendDictionary[Mqtt_sender],sendDictionary[Mqtt_receiver],sendDictionary[Mqtt_msgType],sendDictionary[Mqtt_chatType],msgStr,sendDictionary[Mqtt_sendTime],sendDictionary[Mqtt_receiver]];
        BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
        if (resChange == NO) {
            NSLog(@"修改消息表失败");
        }
    }
    
    return returnInt;
}
- (void)messageToPersonSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus success:(void(^)(int returnInt))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        int returnInt = [[JayClientManager sharedClient] messageToPersonSuccessWithSendDictionary:sendDictionary andMessageStatus:messageStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(returnInt);
        });
    });
}
//修改单聊消息中的messageStatus，传入对方用户ID，消息的uid和新的messageStatus
- (BOOL)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus
{
    //创建一张单聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,personId]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建单聊表失败");
    }
    
    NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set messageStatus='%@' where uid=%@",[NSString stringWithFormat:Table_Person_Format,personId],messageStatus,uidString];
    BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
    if (resChange1 == NO) {
        NSLog(@"修改单聊中的messageStatus失败");
        return resChange1;
    }
    return resChange1;
}
- (void)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus success:(void(^)(BOOL resChange))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        BOOL resChange = [[JayClientManager sharedClient] writeNewMsgInPersonWithPersonID:personId andUID:uidString andMessageStatus:messageStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(resChange);
        });
    });
}



//修改单聊消息中的msg，传入对方用户ID，消息的uid和新的msg
- (BOOL)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMsg:(NSString *)msg
{
    //创建一张单聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,personId]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建单聊表失败");
    }
    
    NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set msg='%@' where uid=%@",[NSString stringWithFormat:Table_Person_Format,personId],msg,uidString];
    BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
    if (resChange1 == NO) {
        NSLog(@"修改单聊中的msg失败");
        return resChange1;
    }
    return resChange1;
}
- (void)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMsg:(NSString *)msg success:(void(^)(BOOL resChange))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        BOOL resChange = [[JayClientManager sharedClient] writeNewMsgInPersonWithPersonID:personId andUID:uidString andMsg:msg];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(resChange);
        });
    });
}
//群聊消息发送时调用,将消息存入数据库,返回uid
- (int)messageToGroupSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus
{
    NSString *createStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,sendDictionary[Mqtt_receiver]]];
    //创建一张群聊表
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createStr];
    if (resTable == NO) {
        NSLog(@"创建群聊表失败");
    }
    
    NSData *msgData = [NSJSONSerialization dataWithJSONObject:sendDictionary[Mqtt_msg] options:0 error:nil];
    NSString *msgStr = [[NSString alloc] initWithData:msgData encoding:NSUTF8StringEncoding];
    NSArray *msgArr = [NSJSONSerialization JSONObjectWithData:[msgStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *afterReadStr = [NSString stringWithFormat:@"%@",msgArr[0]];
    
    int isRead = 1;
    
    if ([[NSString stringWithFormat:@"%@",sendDictionary[Mqtt_msgType]] isEqualToString:MqttMsgTypeEnum_PHOTO]&&[afterReadStr isEqualToString:MqttPhotoMsgTypeEnum_ONCE]) {
        isRead = 0;
    }
    
    NSString *insertStr = [NSString stringWithFormat:@"insert into %@(sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus) values('%@','%@','%@','%@','%@','%@','%@','%@')",[NSString stringWithFormat:Table_Group_Format,sendDictionary[Mqtt_receiver]],sendDictionary[Mqtt_sender],sendDictionary[Mqtt_receiver],sendDictionary[Mqtt_msgType],sendDictionary[Mqtt_chatType],msgStr,sendDictionary[Mqtt_sendTime],[NSString stringWithFormat:@"%d",isRead],messageStatus];
    BOOL res = [[JayClientManager sharedClient].db executeUpdate:insertStr];
    if (res == NO) {
        NSLog(@"添加一条群聊数据失败");
        return 0;
    }
    NSString *returnStr = [NSString stringWithFormat:@"SELECT seq FROM sqlite_sequence WHERE name= '%@' LIMIT 1",[NSString stringWithFormat:Table_Group_Format,sendDictionary[Mqtt_receiver]]];
    int returnInt = [[JayClientManager sharedClient].db intForQuery:returnStr];
    return returnInt;
}
- (void)messageToGroupSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus success:(void(^)(int returnInt))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        int returnInt = [[JayClientManager sharedClient] messageToGroupSuccessWithSendDictionary:sendDictionary andMessageStatus:messageStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(returnInt);
        });
    });
}
//修改群聊消息中的msg，传入对方用户ID，消息的uid和新的messageStatus
- (BOOL)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus
{
    //创建一张群聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,GroupId]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建群聊表失败");
    }
    
    NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set messageStatus='%@' where uid=%@",[NSString stringWithFormat:Table_Group_Format,GroupId],messageStatus,uidString];
    BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
    if (resChange1 == NO) {
        NSLog(@"修改群聊中的messageStatus失败");
        return resChange1;
    }
    return resChange1;
}
- (void)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus success:(void(^)(BOOL resChange))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        BOOL resChange = [[JayClientManager sharedClient] writeNewMsgInGroupWithGroupID:GroupId andUID:uidString andMessageStatus:messageStatus];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(resChange);
        });
    });
}
//修改群聊消息中的msg，传入对方用户ID，消息的uid和新的msg
- (BOOL)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMsg:(NSString *)msg
{
    //创建一张群聊表
    NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,GroupId]];
    BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
    if (resTable == NO) {
        NSLog(@"创建群聊表失败");
    }
    
    NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set msg='%@' where uid=%@",[NSString stringWithFormat:Table_Group_Format,GroupId],msg,uidString];
    BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
    if (resChange1 == NO) {
        NSLog(@"修改群聊中的msg失败");
        return resChange1;
    }
    return resChange1;
}
- (void)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMsg:(NSString *)msg success:(void(^)(BOOL resChange))handle{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        BOOL resChange = [[JayClientManager sharedClient] writeNewMsgInGroupWithGroupID:GroupId andUID:uidString andMsg:msg];
        dispatch_async(dispatch_get_main_queue(), ^{
            handle(resChange);
        });
    });
}

//点击群组中未读的阅后即焚和语音消息时调用(如果该消息为已读消息则不调用)，传入字符串格式的群ID和cell对应的uid，将数据库中对应数据的isRead变为@"1"
- (void)fireAfterReadInGroupWith:(NSString *)groupId andUID:(NSString *)uidString
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        //创建一张群聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Group_Format,groupId]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建群聊表失败");
        }
        
        NSString *updateStr = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%@",[NSString stringWithFormat:Table_Group_Format,groupId],[NSString stringWithFormat:@"1"],uidString];
        BOOL resChange = [[JayClientManager sharedClient].db executeUpdate:updateStr];
        if (resChange == NO) {
            NSLog(@"修改群聊中阅后即焚或语音已读状态失败");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
        });
    });
}

//点击单聊中未读的阅后即焚和语音消息时调用(如果该消息为已读消息则不调用)，传入字符串格式的用户ID和cell对应的uid，将数据库中对应数据的isRead变为@"1",点击自己发的消息时不调用
- (void)fireAfterReadInPersonWith:(NSString *)personId andUID:(NSString *)uidString
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        //创建一张单聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,personId]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建单聊表失败");
        }
        
        NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set isRead='%@' where uid=%@",[NSString stringWithFormat:Table_Person_Format,personId],[NSString stringWithFormat:@"1"],uidString];
        BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
        if (resChange1 == NO) {
            NSLog(@"修改单聊中阅后即焚或语音已读状态失败");
        }
        
        //        //根据单聊记录中的未读消息条数，更新消息表中对应用户ID的msgNumber
        //        NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@ where isRead='0'",[NSString stringWithFormat:Table_Person_Format,personId]];
        //        int count = [[JayClientManager sharedClient].db intForQuery:getCountStr];
        //        
        //        //如果消息表不存在，就创建一张消息表
        //        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber)"];
        //        BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
        //        if (resTableMsg == NO) {
        //            NSLog(@"创建消息表失败");
        //        }
        //        
        //        NSString *updateStr2 = [NSString stringWithFormat:@"update Table_Message set msgNumber=%d where sender='%@'",count,personId];
        //        BOOL resChange2 = [[JayClientManager sharedClient].db executeUpdate:updateStr2];
        //        if (resChange2 == NO) {
        //            NSLog(@"修改消息表失败");
        //        }
        dispatch_async(dispatch_get_main_queue(), ^{
        });
    });
}

//同意加为好友，点击单聊中未读的好友请求消息时调用
- (void)acceptMakeFriendsWithPersonId:(NSString *)personId andUID:(NSString *)uidString
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        //创建一张单聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,personId]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建单聊表失败");
        }
        NSArray *addFriendArr = @[MqttFriendRelationTypeEnum_ADD];
        NSData *addJsonData = [NSJSONSerialization dataWithJSONObject:addFriendArr options:0 error:nil];
        NSString *addFriendString = [[NSString alloc] initWithData:addJsonData encoding:NSUTF8StringEncoding];
        NSString *selectSQL = [NSString stringWithFormat:@"select * from %@ where msg='%@' and msgType='%@'",[NSString stringWithFormat:Table_Person_Format,personId],addFriendString,MqttMsgTypeEnum_FRIEND];

        //查询单聊里所有的好友请求
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:selectSQL];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            //新的msg
            NSArray *msgArr = [NSArray arrayWithObjects:MqttFriendRelationTypeEnum_ADD,MqttFriendRelationTypeEnum_AGREE, nil];
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:msgArr options:0 error:nil];
            NSString *newMsgString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            
            NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set isRead='%@',msg='%@' where uid=%@",[NSString stringWithFormat:Table_Person_Format,personId],[NSString stringWithFormat:@"1"],newMsgString,[NSString stringWithFormat:@"%d",uid]];
            BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
            if (resChange1 == NO) {
                NSLog(@"修改好友请求msg和已读状态失败");
            }else{
                NSLog(@"修改好友请求msg成功");
            }
        }
        
        //        //根据单聊记录中的未读消息条数，更新消息表中对应用户ID的msgNumber
        //        NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@ where isRead='0'",[NSString stringWithFormat:Table_Person_Format,personId]];
        //        int count = [[JayClientManager sharedClient].db intForQuery:getCountStr];
        //        
        //        //如果消息表不存在，就创建一张消息表
        //        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber)"];
        //        BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
        //        if (resTableMsg == NO) {
        //            NSLog(@"创建消息表失败");
        //        }
        //        
        //        NSString *updateStr2 = [NSString stringWithFormat:@"update Table_Message set msgNumber=%d where sender='%@'",count,personId];
        //        BOOL resChange2 = [[JayClientManager sharedClient].db executeUpdate:updateStr2];
        //        if (resChange2 == NO) {
        //            NSLog(@"修改消息表失败");
        //        }
        dispatch_async(dispatch_get_main_queue(), ^{
        });
    });
}
//拒绝加为好友，点击单聊中未读的好友请求消息时调用
- (void)refuseMakeFriendsWithPersonId:(NSString *)personId andUID:(NSString *)uidString
{
    dispatch_async([JayClientManager sharedClient].queue, ^{
        //创建一张单聊表
        NSString *createGroupTableStr = [NSString stringWithFormat:@"create table if not exists %@(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,isRead,messageStatus)",[NSString stringWithFormat:Table_Person_Format,personId]];
        BOOL resTable = [[JayClientManager sharedClient].db executeUpdate:createGroupTableStr];
        if (resTable == NO) {
            NSLog(@"创建单聊表失败");
        }
        NSArray *addFriendArr = @[MqttFriendRelationTypeEnum_ADD];
        NSData *addJsonData = [NSJSONSerialization dataWithJSONObject:addFriendArr options:0 error:nil];
        NSString *addFriendString = [[NSString alloc] initWithData:addJsonData encoding:NSUTF8StringEncoding];
        NSString *selectSQL = [NSString stringWithFormat:@"select * from %@ where msg='%@' and msgType='%@'",[NSString stringWithFormat:Table_Person_Format,personId],addFriendString,MqttMsgTypeEnum_FRIEND];
        
        //查询单聊里所有的好友请求
        FMResultSet* set = [[JayClientManager sharedClient].db executeQuery:selectSQL];
        while ([set next]) {
            int uid = [set intForColumn:@"uid"];
            //新的msg
            NSArray *msgArr = [NSArray arrayWithObjects:MqttFriendRelationTypeEnum_ADD,MqttFriendRelationTypeEnum_REJECT, nil];
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:msgArr options:0 error:nil];
            NSString *newMsgString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            
            NSString *updateStr1 = [NSString stringWithFormat:@"update %@ set isRead='%@',msg='%@' where uid=%@",[NSString stringWithFormat:Table_Person_Format,personId],[NSString stringWithFormat:@"1"],newMsgString,[NSString stringWithFormat:@"%d",uid]];
            BOOL resChange1 = [[JayClientManager sharedClient].db executeUpdate:updateStr1];
            if (resChange1 == NO) {
                NSLog(@"修改好友请求msg和已读状态失败");
            }else{
                NSLog(@"修改好友请求msg和已读状态成功");
            }
            
        }
        
        //        //根据单聊记录中的未读消息条数，更新消息表中对应用户ID的msgNumber
        //        NSString *getCountStr = [NSString stringWithFormat:@"select count(*) from %@ where isRead='0'",[NSString stringWithFormat:Table_Person_Format,personId]];
        //        int count = [[JayClientManager sharedClient].db intForQuery:getCountStr];
        //        
        //        //如果消息表不存在，就创建一张消息表
        //        NSString *createMessageTableStr = [NSString stringWithFormat:@"create table if not exists Table_Message(uid integer primary key autoincrement,sender,receiver,msgType,chatType,msg,sendTime,msgNumber)"];
        //        BOOL resTableMsg = [[JayClientManager sharedClient].db executeUpdate:createMessageTableStr];
        //        if (resTableMsg == NO) {
        //            NSLog(@"创建消息表失败");
        //        }
        //        
        //        NSString *updateStr2 = [NSString stringWithFormat:@"update Table_Message set msgNumber=%d where sender='%@'",count,personId];
        //        BOOL resChange2 = [[JayClientManager sharedClient].db executeUpdate:updateStr2];
        //        if (resChange2 == NO) {
        //            NSLog(@"修改消息表失败");
        //        }
        dispatch_async(dispatch_get_main_queue(), ^{
        });
    });
}

-(void)publishDynamicAfterGetUrl:(JKAssets *)asset success:(void(^)(NSString * urlString))handle{
    dispatch_async([JayClientManager sharedClient].publishDynamicQueue, ^{
            ALAssetsLibrary   *lib = [[ALAssetsLibrary alloc] init];
            [lib assetForURL:asset.assetPropertyURL resultBlock:^(ALAsset *asset) {
                if (asset) {
                    UIImage *image = [UIImage imageWithCGImage:[[asset defaultRepresentation] fullScreenImage]];
                    //超过2M的图片会旋转，所以进行处理，防止图片旋转
                    UIImage *lastImage = [self fixOrientation:image];
                    NSData *imageData=UIImageJPEGRepresentation(lastImage, 1.0);
                    NSString *newString = [imageData base64EncodedStringWithOptions:0];
                    
                    NSURL *imgUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@/imageUploader/uploadCache.shtml",AliYunIndexPage]];
                    
                    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:imgUrl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
                    [request setHTTPMethod:@"POST"];
                    
                    NSString *postStr = [NSString stringWithFormat:@"img=%@",newString];
                    [request setHTTPBody:[postStr dataUsingEncoding:NSUTF8StringEncoding]];
                    NSURLSession *session = [NSURLSession sharedSession];
                    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        if(error || !data){
                            NSLog(@"解析失败");
                        }else{
                            id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
                            NSDictionary *responseDict = (NSDictionary *)json;
                            if ([responseDict[@"state"] isEqualToString:@"success"]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    handle([NSString stringWithFormat:@"%@",[responseDict objectForKey:@"url"]]);
                                });
                            }
                        }
                    }];
                    [dataTask resume];
                }
                
            } failureBlock:^(NSError *error) {
                
            }];

    });
}
- (UIImage *)fixOrientation:(UIImage *)aImage {
    
    // No-op if the orientation is already correct
    if (aImage.imageOrientation == UIImageOrientationUp)
        return aImage;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, aImage.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, aImage.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        default:
            break;
    }
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        default:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, aImage.size.width, aImage.size.height,
                                             CGImageGetBitsPerComponent(aImage.CGImage), 0,
                                             CGImageGetColorSpace(aImage.CGImage),
                                             CGImageGetBitmapInfo(aImage.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (aImage.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.height,aImage.size.width), aImage.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.width,aImage.size.height), aImage.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}



/**
 *  本地通知
 *
 *  @param body
 */
- (void)sendLocalNotification:(NSMutableDictionary *)body
{
    self.localNotification = [[UILocalNotification alloc] init];
    //触发通知时间
    //        NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:alertTime];
    //        _localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:alertTime];
    //重复间隔
    //        _localNotification.repeatInterval = 0;
    //时区  根据用户手机的位置来显示不同的时区
    self.localNotification.timeZone = [NSTimeZone defaultTimeZone];
    //声音
    NSString *bodyStr = [body objectForKey:@"localBody"];
    
    //通知内容
    self.localNotification.alertBody = bodyStr;
    self.localNotification.alertAction = bodyStr;
    self.localNotification.userInfo = body;
    NSInteger badge = [UIApplication sharedApplication].applicationIconBadgeNumber;
    if (badge != 0) {
        badge += 1;
        self.localNotification.applicationIconBadgeNumber = badge;
    }else{
        self.localNotification.applicationIconBadgeNumber = 1;
    }
    
    
    // 通知被触发时播放的声音
    self.localNotification.soundName = UILocalNotificationDefaultSoundName;
    
    //self.localNotification.category = MyNotificationCategoryIdentifile;
    
    [[UIApplication sharedApplication] scheduleLocalNotification:self.localNotification];
    
}
/**
 *  来消息的声音提醒
 */
-(void)messageComeWithVoice{
    // 要播放的音频文件地址
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"shake_match" ofType:@"mp3"];
    NSURL *filePath = [NSURL fileURLWithPath:bundlePath isDirectory:NO];
    
    //     创建系统声音，同时返回一个ID
    SystemSoundID soundID;
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)(filePath), &soundID);
    // Register the sound completion callback.
    AudioServicesPlaySystemSound(soundID);
    
}



//+ (void)registerLocalNotification:(NSInteger)alertTime {
//    UILocalNotification *notification = [[UILocalNotification alloc] init];
//    // 设置触发通知的时间
//    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:alertTime];
//    NSLog(@"fireDate=%@",fireDate);
//    
//    notification.fireDate = fireDate;
//    // 时区
//    notification.timeZone = [NSTimeZone defaultTimeZone];
//    // 设置重复的间隔
//    notification.repeatInterval = kCFCalendarUnitSecond;
//    
//    // 通知内容
//    notification.alertBody =  @"该起床了...";
//    notification.applicationIconBadgeNumber = 1;
//    // 通知被触发时播放的声音
//    notification.soundName = UILocalNotificationDefaultSoundName;
//    // 通知参数
//    NSDictionary *userDict = [NSDictionary dictionaryWithObject:@"开始学习iOS开发了" forKey:@"key"];
//    notification.userInfo = userDict;
//    
//    // ios8后，需要添加这个注册，才能得到授权
//    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
//        UIUserNotificationType type =  UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
//        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:type
//                                                                                 categories:nil];
//        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
//        // 通知重复提示的单位，可以是天、周、月
//        notification.repeatInterval = NSCalendarUnitDay;
//    } else {
//        // 通知重复提示的单位，可以是天、周、月
//        notification.repeatInterval = NSDayCalendarUnit;
//    }
//    
//    // 执行通知注册
//    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
//}




@end
